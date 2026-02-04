# OpenCode.md

## Build, Lint, and Test Commands

### Build
- To compile the project: `mix compile`
- To set up the project: `mix setup`

### Lint
- To format the code: `mix format`
- To use static analysis (e.g., Credo): `mix credo`
- To check for security vulnerabilities: `mix sobelow`

### Test
- To run all tests: `mix test`
- To prepare the test database and run tests: `mix test`
- To run a single test file: `mix test path/to/file.exs`
- To run a single test within a file: `mix test path/to/file.exs:line_number`

## Code Style Guidelines

### Imports and Dependencies
- Use `alias`, `require`, and `import` where needed, following module namespacing conventions.
- Declare dependencies in `mix.exs`.

### Formatting
- Use `mix format` to ensure consistent code style.
- Adhere to the community-recommended Elixir conventions.

### Modules and Naming
- Use `PascalCase` for module names and `snake_case` for functions and variables.
- Namespaces reflect functionality (e.g., `YscWeb.Live` for LiveView components).

### Error Handling
- Use `try/rescue` sparingly, and opt for pattern matching and `with` chains.
- Return idiomatic tuples like `{:ok, result}` and `{:error, reason}`.

### Testing
- Organize tests by feature or functionality in the `test/` directory.
- Follow `descriptive test names` for context clarity.

### Types
- Use `@spec` for public functions.
- Prefer Elixir types (`{:ok, any()}`) for consistency.

## Workflow
- Use `mix precommit` to check and format code before commit.
- Strictly adhere to the commit guidelines.

Following these practices ensures seamless collaboration and maintainability. 🤖 Generated with OpenCode.