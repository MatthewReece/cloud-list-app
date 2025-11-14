🛒 Cloud Shopping List MVP

A secure, real-time Minimum Viable Product (MVP) for managing a shopping list. This project showcases proficiency in modern full-stack development using the React/Next.js frontend ecosystem combined with a robust, serverless infrastructure on Amazon Web Services (AWS).

🌟 Key Features

Secure Authentication: User sign-up and sign-in managed entirely by AWS Cognito.

Serverless CRUD: Full Create, Read, Update, and Delete (CRUD) functionality powered by AWS Lambda and DynamoDB.

Optimized Hosting: High-performance, low-latency delivery via AWS S3 (storage) and AWS CloudFront (CDN).

Responsive UI: Built with React and styled using Tailwind CSS for a seamless experience on mobile and desktop.

⚙️ Technology Stack

Component

Technology

Role

Frontend

Next.js (Static Export), React, Tailwind CSS

Client-side logic, routing, UI rendering, and styling.

Authentication

AWS Cognito (Modular v6)

User identity, sign-up, sign-in, and OAuth flow management.

API Layer

AWS API Gateway

Secure, scalable REST API endpoint for Lambda integration.

Compute

AWS Lambda (Node.js)

Serverless execution environment for all business logic (CRUD operations).

Database

AWS DynamoDB

NoSQL database for storing and retrieving shopping list items.

Deployment

AWS S3, AWS CloudFront

Static hosting and global content delivery network (CDN).

🏗️ Cloud Architecture & Data Flow

This application is built on a scalable, serverless stack. The entire front-end is static, and all dynamic behavior is handled by AWS managed services.

User Access: Users access the application via the CloudFront CDN URL, which serves the static files from the S3 bucket.

Authentication: Sign-in redirects the user to the Cognito Hosted UI. Upon successful login, the user is redirected back to the CloudFront URL with a valid session token.

API Call: The React frontend makes a secured HTTP request to the API Gateway endpoint, including the Cognito session token in the request headers.

Backend Processing: API Gateway routes the request to the appropriate Lambda function.

Data Interaction: The Lambda function executes the CRUD logic against the DynamoDB table.

💡 Lessons Learned & Technical Challenges

The successful deployment of this stack required solving several advanced configuration and environment issues, which are critical for production readiness.

1. ⚠️ Critical AWS Amplify V5 to V6 Migration

Challenge: The project began using the older, global Amplify V5 structure. A necessary switch to the modern, modular V6 structure introduced significant breaking changes in API access and component usage, creating major confusion around dependency imports and configuration file referencing.

Resolution: Successfully refactored the entire authentication flow, moving from global Amplify.configure() calls to targeted modular imports (e.g., @aws-amplify/auth). This demonstrated an ability to adapt to rapid SDK changes and integrate modern, tree-shakeable AWS libraries.

2. Next.js Static Environment Variable Injection

Challenge: Next.js, when configured for static export (output: 'export'), intentionally ignores standard environment variables (like REACT*APP*). The deployed app initially failed because the critical API URL was resolving as undefined.

Resolution: Correctly implemented the NEXT*PUBLIC* prefix across the codebase and configuration. The final URL was explicitly injected into the static build files via the package.json build script to guarantee its presence at deploy time, resolving the runtime configuration failure.

3. Configuration Guardrail Implementation

Challenge: An application must fail immediately during deployment if a critical API URL is missing, rather than failing silently at runtime.

Resolution: A TypeScript guardrail was implemented in the main component to immediately throw a specific, descriptive configuration error if the required API URL was missing. This prevents silent production failures and alerts the developer immediately to a configuration error.

4. AWS Cognito Redirect Management

Challenge: The Cognito OAuth flow requires the exact live URL to be specified on the backend. Hardcoded local URLs (localhost:3000) caused redirect failures after deployment to the CDN.

Resolution: The live CloudFront Domain Name was added to the "Allowed callback URLs" list within the Cognito User Pool's App Client settings, ensuring a successful and secure redirect upon successful user login.

🚀 Getting Started Locally

To run this project on your machine, you will need Node.js and the AWS CLI configured.

Clone the repository and install dependencies:

git clone [YOUR_REPO_URL]
cd cloud-list-app/frontend
npm install

Configure Environment Variables:
Create a file named .env.local in the frontend/ directory and add your development API URL and Cognito details.

# frontend/.env.local

NEXT_PUBLIC_API_URL=[https://jr1fnxnx7c.execute-api.us-east-1.amazonaws.com/dev/items](https://jr1fnxnx7c.execute-api.us-east-1.amazonaws.com/dev/items)

# Add your Cognito IDs here for local testing

NEXT_PUBLIC_COGNITO_USER_POOL_ID=...

Run the application:

npm run dev

The application will be accessible at http://localhost:3000.
