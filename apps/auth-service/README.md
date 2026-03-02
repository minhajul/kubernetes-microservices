## Auth Service

The Auth Service is a microservice built with Laravel. It provides user authentication and authorization functionalities
for the larger system, utilizing Laravel Sanctum for API token management.

### Features

- **User Registration:** Provide endpoints to register new users.
- **User Login:** Authenticate and issue API tokens.
- **User Logout:** Revoke active tokens.
- **User Information:** Retrieve details of the authenticated user.
- **Containerized:** Includes a `Dockerfile` for easy containerization and deployment within a Kubernetes or Docker
  environment.

### Prerequisites

- **PHP:** >= 8.2
- **Composer:** Dependency manager for PHP.
- **Node.js & NPM:** (Optional, for building/compiling any local assets via Vite)
- **Docker:** (Optional, if running via container)

### Installation & Setup

1. **Navigate to the service directory:**
   ```bash
   cd apps/auth-service
   ```

2. **Install dependencies:**
   ```bash
   composer install
   ```

3. **Set up environment variables:**
   Copy the example environment file to create your local configuration:
   ```bash
   cp .env.example .env
   ```

4. **Generate the application key:**
   ```bash
   php artisan key:generate
   ```

5. **Database Configuration & Migrations:**
   By default, this service is set up to use an SQLite database (`database/database.sqlite`).
   To run migrations:
   ```bash
   touch database/database.sqlite
   php artisan migrate
   ```
   *(Note: You can update the `DB_CONNECTION` and other `DB_*` variables in the `.env` file to connect to MySQL or
   PostgreSQL).*

### Running the Application Locally

You can use the built-in Composer `dev` script or `Laravel's` development server:

```bash
composer run dev
```

Alternatively, you can just run the server:

```bash
php artisan serve
```

The service will be accessible by default at `http://localhost:8000`.

### API Endpoints

All API endpoints reside within the `/api` prefix and return JSON responses.

#### Public Endpoints

- **`GET /api/`**
    - **Description:** Health check / basic response endpoint.
- **`POST /api/register`**
    - **Description:** Register a new user account.
- **`POST /api/login`**
    - **Description:** Authenticate user credentials and return a Sanctum API token.

#### Protected Endpoints (Require Bearer Token)

These endpoints require an `Authorization: Bearer <token>` header, where the token is obtained from the login route.

- **`GET /api/user`**
    - **Description:** Retrieve the currently authenticated user's information.
- **`POST /api/logout`**
    - **Description:** Log out the currently authenticated user and revoke their current token.

### Code Quality & Testing

This project uses [Pest PHP](https://pestphp.com/) for its test suite and Laravel Pint for code styling.

**Running Tests:**

```bash
composer test
# OR
php artisan test
```

**Running Linter (Pint):**

```bash
composer run lint
```

### Docker / Deployment

A `Dockerfile` is provided in the project root to build an image for the service.

```bash
docker build -t microservices-auth-service .
```
