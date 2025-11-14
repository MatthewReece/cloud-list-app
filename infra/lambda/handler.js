const { DynamoDBClient, PutItemCommand, ScanCommand, UpdateItemCommand, DeleteItemCommand } = require("@aws-sdk/client-dynamodb");
const { unmarshall, marshall } = require("@aws-sdk/util-dynamodb");
const crypto = require('crypto');

const client = new DynamoDBClient({ region: process.env.AWS_REGION });
const TABLE_NAME = process.env.TABLE_NAME;

// -------------------------------------------------------------
// Helper to get the authenticated user ID from the API Gateway event
// -------------------------------------------------------------
const getUserId = (event) => {
    // When using a Cognito Authorizer with AWS_PROXY, the claims are in the authorizer context.
    try {
        const claims = event.requestContext.authorizer.claims;

        // CRITICAL FIX: Access Tokens often pass the user ID as 'cognito:username'.
        // We check for the most common claims in order of reliability.
        const userId = claims['cognito:username'] || claims.username || claims.sub; 

        if (!userId) {
            console.error("User ID (sub/username) not found in Cognito claims. Claims object:", claims);
            // Throwing an error is the safest way to prevent unauthorized DB access.
            throw new Error("Authorization context is missing a User ID."); 
        }
        return userId;
    } catch (e) {
        // If the entire context is missing (no token provided/failed authorization)
        console.error("Error accessing authorizer claims:", e);
        // Throwing an error ensures a non-authenticated request fails with a 401/403.
        throw new Error("Unauthorized access: User identity could not be retrieved.");
    }
}

// Define common CORS headers to allow local/frontend access
const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*', 
    'Access-Control-Allow-Headers': 'Content-Type,Authorization', 
    'Access-Control-Allow-Methods': 'OPTIONS,POST,GET,PUT,DELETE' 
};

// Helper function for required input validation 
const validateInput = (body) => {
    if (!body || typeof body !== 'object') {
        return "Request body is invalid or missing.";
    }
    if (!body.itemName || typeof body.itemName !== 'string') {
        return "Missing or invalid 'itemName'.";
    }
    if (typeof body.quantity !== 'number' || body.quantity <= 0) {
        return "Missing or invalid 'quantity'. Must be a positive number.";
    }
    return null; // Validation passed
};


exports.handler = async (event) => {
  console.log("Event:", event);
  
  // Get the dynamic, authenticated userId as the very first step
  let userId;
  try {
      userId = getUserId(event); 
  } catch (e) {
      // If getUserId fails, return a proper unauthorized response
      return { statusCode: 401, headers: CORS_HEADERS, body: JSON.stringify({ error: e.message }) };
  }

  // Handle the OPTIONS pre-flight check explicitly
  if (event.httpMethod === "OPTIONS") {
      return { statusCode: 204, headers: CORS_HEADERS };
  }

  try {
    if (event.httpMethod === "GET") {
      // -------------------------------------------------------------
      // GET: Retrieve all items for the authenticated user
      // -------------------------------------------------------------
      const scanCommand = new ScanCommand({ 
          TableName: TABLE_NAME,
          // Filter to only get items belonging to the authenticated user
          FilterExpression: "userId = :uid", 
          ExpressionAttributeValues: {
              ":uid": { S: userId } // Use dynamic userId
          }
      });
      
      const data = await client.send(scanCommand);
      const cleanItems = data.Items.map(item => unmarshall(item)); 
      
      return { statusCode: 200, headers: CORS_HEADERS, body: JSON.stringify(cleanItems) };
      
    } else if (event.httpMethod === "POST") {
      // -------------------------------------------------------------
      // POST: Add a new item for the authenticated user
      // -------------------------------------------------------------
      const body = JSON.parse(event.body);
      const validationError = validateInput(body);
      if (validationError) {
          return { statusCode: 400, headers: CORS_HEADERS, body: JSON.stringify({ error: validationError }) };
      }

      const itemToSave = {
          itemId: crypto.randomBytes(16).toString('hex'), 
          userId: userId, // Use dynamic userId
          createdAt: new Date().toISOString(),
          checked: false,
          ...body, 
      };

      const marshalledItem = marshall(itemToSave);
      await client.send(new PutItemCommand({ TableName: TABLE_NAME, Item: marshalledItem }));
      
      return { 
          statusCode: 201, 
          headers: CORS_HEADERS, 
          body: JSON.stringify({ message: "Item successfully added", item: itemToSave }) 
      };
      
    } else if (event.httpMethod === "PUT") {
      // -------------------------------------------------------------
      // PUT: Update item status for the authenticated user
      // -------------------------------------------------------------
      const body = JSON.parse(event.body);

      if (!body.itemId || typeof body.checked === 'undefined') {
          return { statusCode: 400, headers: CORS_HEADERS, body: JSON.stringify({ error: "Missing required fields: itemId and checked status." }) };
      }
      
      const updateCommand = new UpdateItemCommand({
          TableName: TABLE_NAME,
          Key: marshall({ // Key must include dynamic Partition (userId) and Sort (itemId) Keys
              userId: userId, // Use dynamic userId
              itemId: body.itemId, 
          }),
          UpdateExpression: "SET #c = :c",
          ExpressionAttributeNames: { "#c": "checked" },
          ExpressionAttributeValues: { ":c": { BOOL: body.checked } },
          ReturnValues: "ALL_NEW", 
      });

      const result = await client.send(updateCommand);
      const updatedItem = unmarshall(result.Attributes);

      return { 
          statusCode: 200, 
          headers: CORS_HEADERS,
          body: JSON.stringify(updatedItem) 
      };
      
    } else if (event.httpMethod === "DELETE") {
      // -------------------------------------------------------------
      // DELETE: Remove checked items for the authenticated user
      // -------------------------------------------------------------
      
      // 1. Scan to find all checked items for *this specific user*
      const scanCommand = new ScanCommand({ 
          TableName: TABLE_NAME,
          // Filter by both userId AND checked status
          FilterExpression: "userId = :uid AND #c = :true", 
          ExpressionAttributeNames: { "#c": "checked" },
          ExpressionAttributeValues: { 
              ":true": { BOOL: true },
              ":uid": { S: userId } // Use dynamic userId
          },
          ProjectionExpression: "itemId" 
      });
      const itemsToDelete = await client.send(scanCommand);

      if (itemsToDelete.Count === 0) {
          return { statusCode: 204, headers: CORS_HEADERS, body: "" };
      }

      // 2. Create and execute all deletions concurrently
      const deletePromises = itemsToDelete.Items.map(item => {
          const { itemId } = unmarshall(item); 
          return client.send(new DeleteItemCommand({
              TableName: TABLE_NAME,
              // Key must include dynamic Partition (userId) and Sort (itemId) Keys
              Key: marshall({ 
                  userId: userId, // Use dynamic userId
                  itemId: itemId      
              })
          }));    
      });

      await Promise.all(deletePromises);

      return { statusCode: 204, headers: CORS_HEADERS, body: "" };
      
    } else {
      // Catch-all for methods not supported
      return { 
          statusCode: 405, 
          headers: CORS_HEADERS, 
          body: "Method Not Allowed" 
      };
    }
  } catch (err) {
    console.error(err);
    // Return a generic 500 without internal details for better security
    return { 
        statusCode: 500, 
        headers: CORS_HEADERS, 
        body: JSON.stringify({ error: "An unexpected server error occurred." }) 
    };
  }
};