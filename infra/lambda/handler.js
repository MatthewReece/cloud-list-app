const { DynamoDBClient, PutItemCommand, ScanCommand, UpdateItemCommand, DeleteItemCommand } = require("@aws-sdk/client-dynamodb");
const { unmarshall, marshall } = require("@aws-sdk/util-dynamodb");
const crypto = require('crypto');

const client = new DynamoDBClient({ region: process.env.AWS_REGION });
const TABLE_NAME = process.env.TABLE_NAME;

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
  
  // Handle the OPTIONS pre-flight check explicitly
  if (event.httpMethod === "OPTIONS") {
      return { statusCode: 204, headers: CORS_HEADERS };
  }

  try {
    if (event.httpMethod === "GET") {
      // ... (GET Logic)
      const data = await client.send(new ScanCommand({ TableName: TABLE_NAME }));
      const cleanItems = data.Items.map(item => unmarshall(item)); 
      return { statusCode: 200, headers: CORS_HEADERS, body: JSON.stringify(cleanItems) };
      
    } else if (event.httpMethod === "POST") {
      // ... (POST Logic)
      const body = JSON.parse(event.body);
      const validationError = validateInput(body);
      if (validationError) {
          return { statusCode: 400, headers: CORS_HEADERS, body: JSON.stringify({ error: validationError }) };
      }

      const itemToSave = {
          itemId: crypto.randomBytes(16).toString('hex'), 
          userId: 'user-123', 
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
      // Status Update (Check Off Item)
      const body = JSON.parse(event.body);

      if (!body.itemId || typeof body.checked === 'undefined') {
          return { statusCode: 400, headers: CORS_HEADERS, body: JSON.stringify({ error: "Missing required fields: itemId and checked status." }) };
      }
      
      const updateCommand = new UpdateItemCommand({
          TableName: TABLE_NAME,
          Key: marshall({ // The Key must include BOTH Partition (userId) and Sort (itemId) Keys
              userId: 'user-123', // <--  Static Partition Key (must match POST logic)
              itemId: body.itemId, // The Sort Key passed from the frontend
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
      // Delete all items with checked: true status
      
      // Scan to find all checked items (only need itemId)
      const scanCommand = new ScanCommand({ 
          TableName: TABLE_NAME,
          FilterExpression: "#c = :true", 
          ExpressionAttributeNames: { "#c": "checked" },
          ExpressionAttributeValues: { ":true": { BOOL: true } },
          ProjectionExpression: "itemId" 
      });
      const itemsToDelete = await client.send(scanCommand);

      if (itemsToDelete.Count === 0) {
          return { statusCode: 204, headers: CORS_HEADERS, body: "" };
      }

      // Create and execute all deletions concurrently
      const deletePromises = itemsToDelete.Items.map(item => {
          const { itemId } = unmarshall(item); 
          return client.send(new DeleteItemCommand({
              TableName: TABLE_NAME,
              Key: marshall({ 
                  userId: 'user-123', // <-- ADDED STATIC Partition Key
                  itemId: itemId      // <-- Sort Key from the scan
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