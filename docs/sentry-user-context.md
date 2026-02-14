# Sentry User Context in JavaScript

## Overview

The application automatically sets Sentry user context for logged-in users to improve error tracking and debugging. This allows you to see which users are experiencing errors in your Sentry dashboard.

## Automatic User Context

User context is automatically set on page load based on the `@current_user` assign in the root layout. The following information is sent to Sentry:

- `id`: User's ULID
- `email`: User's email address
- `role`: User's role (`:user`, `:admin`, etc.)
- `state`: User's account state (`:active`, `:pending_approval`, etc.)

## Manual Updates from LiveView

If you need to update the Sentry user context after a user logs in or out within a LiveView (without a full page reload), you can push a custom event:

### When User Logs In

```elixir
def handle_event("login", params, socket) do
  # Your login logic here
  user = authenticate_user(params)
  
  # Update Sentry context on the client
  {:noreply,
   socket
   |> assign(:current_user, user)
   |> push_event("update-sentry-user", %{
     user: %{
       id: user.id,
       email: user.email,
       role: user.role,
       state: user.state
     }
   })}
end
```

### When User Logs Out

```elixir
def handle_event("logout", _params, socket) do
  # Your logout logic here
  
  # Clear Sentry context on the client
  {:noreply,
   socket
   |> assign(:current_user, nil)
   |> push_event("update-sentry-user", %{user: nil})}
end
```

## Implementation Details

### Root Layouts

Both `root.html.heex` and `admin_root.html.heex` expose user data via `window.currentUser`:

```javascript
window.currentUser = {
  id: "01JCXAMPLE123",
  email: "user@example.com",
  role: "user",
  state: "active"
};
```

For anonymous users:

```javascript
window.currentUser = null;
```

### JavaScript Handler

The `app.js` file listens for the `phx:update-sentry-user` event and updates both:
1. Sentry user context via `window.Sentry.setUser()`
2. `window.currentUser` for consistency

## Security Notes

- Only non-sensitive user data (id, email, role, state) is exposed
- User context is properly cleared on logout
- All data transmission follows CSP policies

## Testing

To verify Sentry user context is working:

1. Log in as a user
2. Open browser console
3. Check `window.currentUser` - should show user data
4. Trigger an error (intentionally)
5. Check Sentry dashboard - error should be tagged with user information

## Related Files

- `/lib/ysc_web/components/layouts/root.html.heex` - Main layout with user context
- `/lib/ysc_web/components/layouts/admin_root.html.heex` - Admin layout with user context
- `/assets/js/app.js` - Sentry initialization and user context handling
- `/lib/ysc_web/user_auth.ex` - User authentication and session management
