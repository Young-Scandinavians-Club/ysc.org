defmodule YscWeb.Router do
  use YscWeb, :router

  # Removed Bling.Router import - will implement custom billing routes
  import Phoenix.LiveDashboard.Router
  import YscWeb.UserAuth
  import YscWeb.Plugs.SiteSettingsPlugs

  # Check if we're in production by checking Mix.env() at compile time
  # In releases, Mix is not available, so we default to production behavior
  @is_prod (if Code.ensure_loaded?(Mix) do
              Mix.env() == :prod
            else
              true
            end)

  pipeline :feed do
    plug :accepts, ["atom", "xml", "html"]

    if @is_prod do
      plug Plug.SSL, rewrite_on: [:x_forwarded_proto], max_age: 31_536_000
    end

    plug YscWeb.Plugs.FeedHeaders
    plug :put_secure_browser_headers
  end

  pipeline :browser do
    plug :accepts, ["html"]

    plug :fetch_session
    plug :fetch_live_flash

    plug :put_root_layout, html: {YscWeb.Layouts, :root}

    plug :protect_from_forgery

    # Enforce SSL/HSTS (Strict-Transport-Security) - only in production
    # In production, this redirects HTTP to HTTPS and sets HSTS header
    # In development, we skip this to avoid redirect loops and HSTS caching issues
    # HSTS header is set explicitly in SecurityHeaders plug (production only)
    if @is_prod do
      plug Plug.SSL, rewrite_on: [:x_forwarded_proto], max_age: 31_536_000
    end

    # Generate a Nonce for CSP (must come before security headers)
    plug YscWeb.Plugs.CSPNonce

    # Set security headers including CSP with nonce
    plug YscWeb.Plugs.SecurityHeaders

    # Standard Phoenix security headers (complements our custom headers)
    plug :put_secure_browser_headers

    plug :fetch_current_user
    plug :mount_site_settings
  end

  # Pipeline for token-login GET pages that render a CSRF-protected POST form.
  # protect_from_forgery must run here so get_csrf_token/0 in the template loads
  # the session token instead of generating an ephemeral one that POST cannot verify.
  pipeline :auto_login do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  # POST handlers for token login require CSRF to prevent login CSRF via cross-site GET.
  pipeline :token_login do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  # Rate limit all auth endpoints by IP (and per-identifier in controllers) to slow down credential stuffing.
  # Covers: email/password (POST /users/log-in), passkey (GET/POST /users/log-in/passkey),
  # auto-login (GET/POST /users/log-in/auto), OAuth (GET /auth/:provider, callback), forgot/reset password.
  pipeline :auth_rate_limit do
    plug YscWeb.Plugs.AuthRateLimitPlug
  end

  pipeline :admin_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {YscWeb.Layouts, :admin_root}
    plug :protect_from_forgery
    plug YscWeb.Plugs.NoIndex

    # Enforce SSL/HSTS - only in production
    if @is_prod do
      plug Plug.SSL, rewrite_on: [:x_forwarded_proto], max_age: 31_536_000
    end

    # Generate a Nonce for CSP (must come before security headers)
    plug YscWeb.Plugs.CSPNonce

    # Set security headers including CSP with nonce
    plug YscWeb.Plugs.SecurityHeaders

    # Standard Phoenix security headers (complements our custom headers)
    plug :put_secure_browser_headers

    plug :fetch_current_user
    plug :mount_site_settings
    plug YscWeb.Plugs.AdminSidebarState
  end

  pipeline :full_admin_only do
    plug :require_full_admin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :mobile_api_rate_limit do
    plug YscWeb.Plugs.MobileAPIRateLimitPlug
  end

  pipeline :mobile_api do
    plug :accepts, ["json"]
    plug YscWeb.Plugs.MobileAPIAuth
  end

  scope "/api/v1/mobile", YscWeb.Api do
    pipe_through [:mobile_api_rate_limit, :mobile_api]

    get "/bookings/lookup", BookingsController, :lookup
    get "/bookings/calendar", BookingsController, :calendar
    get "/bookings", BookingsController, :index
    get "/properties/:property/info", PropertiesController, :info
    get "/events", EventsController, :index
    post "/check-in", CheckInsController, :create
  end

  scope "/", YscWeb do
    pipe_through [:feed]

    get "/feeds/events.atom", FeedController, :events
    get "/feeds/posts.atom", FeedController, :posts
    get "/sitemap.xml", SitemapController, :index
  end

  scope "/", YscWeb do
    get "/robots.txt", SitemapController, :robots
  end

  scope "/", YscWeb do
    pipe_through [:browser]

    get "/lake-tahoe-cabin", LegacyRedirectController, :tahoe_booking

    get "/lake-tahoe-cabin/tahoe-cabin-booking",
        LegacyRedirectController,
        :tahoe_booking

    get "/clear-lake-cabin", LegacyRedirectController, :clear_lake_booking

    get "/clear-lake-cabin/clear-lake-booking-calendar",
        LegacyRedirectController,
        :clear_lake_booking

    get "/login-2", LegacyRedirectController, :login
    get "/register", LegacyRedirectController, :register

    get "/history", PageController, :history
    get "/board", PageController, :board
    get "/bylaws", PageController, :bylaws
    get "/code-of-conduct", PageController, :code_of_conduct
    get "/privacy-policy", PageController, :privacy_policy
    get "/terms-of-service", PageController, :terms_of_service
    get "/choir", PageController, :choir

    get "/up", UpController, :index
    get "/up/dbs", UpController, :databases

    live_session :mount_site_settings,
      on_mount: [
        {YscWeb.LiveToastMount, :mount_toasts_sync},
        {YscWeb.UserAuth, :mount_current_user},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings},
        {YscWeb.Plugs.RequestPath, :set_request_path}
      ] do
      live "/", HomeLive, :index

      live "/posts/:id", PostLive, :index

      live "/events", EventsLive, :index
      live "/events/:id", EventDetailsLive, :index
      live "/events/:id/tickets", EventDetailsLive, :tickets

      live "/volunteer", VolunteerLive, :index
      live "/report-conduct-violation", ConductViolationReportLive, :index
      live "/contact", ContactLive, :index

      live "/news", NewsLive, :index

      live "/newsletters", NewsletterArchiveLive, :index
      live "/newsletters/:id", NewsletterArchiveLive, :show

      live "/newsletter/unsubscribe/:token", NewsletterUnsubscribeLive, :index
      live "/newsletter/confirm/:token", NewsletterConfirmLive, :index

      live "/bookings/tahoe", TahoeBookingLive, :index

      live "/bookings/clear-lake", ClearLakeBookingLive, :index
      live "/bookings/checkout/:booking_id", BookingCheckoutLive, :index
      live "/bookings/:booking_id/change", BookingChangeLive, :index
      live "/bookings/:booking_id/receipt", BookingReceiptLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", YscWeb do
  #   pipe_through :api
  # end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:ysc, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/dev", YscWeb do
      pipe_through :browser

      live_session :dev_button_showcase,
        on_mount: [
          {YscWeb.LiveToastMount, :mount_toasts_sync},
          {YscWeb.UserAuth, :mount_current_user},
          {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings},
          {YscWeb.Plugs.RequestPath, :set_request_path}
        ] do
        live "/button-showcase", DevButtonShowcaseLive, :index
        live "/avatar-showcase", DevAvatarShowcaseLive, :index
      end
    end
  end

  ## Authentication routes

  scope "/", YscWeb do
    pipe_through [
      :browser,
      :redirect_if_user_is_authenticated,
      :auth_rate_limit
    ]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [
        {YscWeb.LiveToastMount, :mount_toasts_sync},
        {YscWeb.UserAuth, :redirect_if_user_is_authenticated},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings},
        {YscWeb.Plugs.RequestPath, :set_request_path}
      ] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log-in", UserLoginLive, :new
    end
  end

  ## OAuth routes (allow unauthenticated access)
  scope "/auth", YscWeb do
    pipe_through [:browser, :auth_rate_limit]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  ## First-party OAuth (authorization code + PKCE)
  ## `/oauth/query-console/*` kept as aliases for the Query Console app.
  scope "/oauth", YscWeb do
    pipe_through [:browser, :require_authenticated_user, :auth_rate_limit]

    get "/authorize", OAuthController, :authorize
    get "/query-console/authorize", OAuthController, :authorize
  end

  scope "/oauth", YscWeb do
    pipe_through [:browser, :auth_rate_limit]

    get "/logout", OAuthController, :logout
    get "/query-console/logout", OAuthController, :logout
  end

  scope "/oauth", YscWeb do
    pipe_through [:api, :auth_rate_limit]

    post "/token", OAuthController, :token
    post "/query-console/token", OAuthController, :token
  end

  ## Token login: GET renders an auto-submit form; POST consumes the one-time token.
  scope "/", YscWeb do
    pipe_through [:auto_login, :auth_rate_limit]

    get "/users/log-in/auto", UserSessionController, :auto_login
    get "/users/log-in/passkey", UserSessionController, :passkey_login
  end

  scope "/", YscWeb do
    pipe_through [:token_login, :auth_rate_limit]

    post "/users/log-in/auto", UserSessionController, :create_auto_login
    post "/users/log-in/passkey", UserSessionController, :create_passkey_login
  end

  ## Password reset (allow unauthenticated access)
  scope "/", YscWeb do
    pipe_through [
      :browser,
      :redirect_if_user_is_authenticated,
      :auth_rate_limit
    ]

    live_session :password_reset,
      on_mount: [
        {YscWeb.LiveToastMount, :mount_toasts_sync},
        {YscWeb.UserAuth, :mount_current_user},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings},
        {YscWeb.Plugs.RequestPath, :set_request_path}
      ] do
      live "/users/reset-password", UserForgotPasswordLive, :new
      live "/users/reset-password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log-in", UserSessionController, :create
    get "/users/log-in/reset-attempts", UserSessionController, :reset_attempts
  end

  ## Account setup (allow access to both authenticated and unauthenticated users)
  scope "/", YscWeb do
    # No redirect_if_user_is_authenticated
    pipe_through [:browser]

    live_session :account_setup,
      on_mount: [
        {YscWeb.LiveToastMount, :mount_toasts_sync},
        {YscWeb.UserAuth, :mount_current_user},
        {YscWeb.AccountSetupAccess, :default},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings},
        {YscWeb.Plugs.RequestPath, :set_request_path}
      ] do
      live "/account/setup/:user_id", AccountSetupLive, :setup
    end
  end

  scope "/", YscWeb do
    pipe_through [:browser, :require_authenticated_user]

    # Post-migration onboarding route — does NOT include ensure_onboarding_complete
    # to avoid redirect loops. All other authenticated routes redirect here if needed.
    live_session :post_migration_onboarding,
      on_mount: [
        {YscWeb.LiveToastMount, :mount_toasts_sync},
        {YscWeb.UserAuth, :ensure_authenticated},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings},
        {YscWeb.Plugs.RequestPath, :set_request_path}
      ] do
      live "/onboarding", PostMigrationOnboardingLive, :index
    end
  end

  # Member financial documents — approved members only (not pending applicants).
  scope "/", YscWeb do
    pipe_through [
      :browser,
      :require_authenticated_user,
      :require_onboarding_complete,
      :require_approved
    ]

    get "/financials", PageController, :financials
    get "/annual_meetings/*path", AnnualMeetingDocumentController, :show
  end

  scope "/", YscWeb do
    pipe_through [
      :browser,
      :require_authenticated_user,
      :require_onboarding_complete
    ]

    get "/expensereport/files/:encoded_path", ExpenseReportFileController, :show
    get "/wallet/tickets/:ticket_id", AppleWalletController, :ticket
    get "/wallet/membership", AppleWalletController, :membership

    live_session :require_authenticated_user,
      on_mount: [
        {YscWeb.LiveToastMount, :mount_toasts_sync},
        {YscWeb.UserAuth, :ensure_authenticated},
        {YscWeb.UserAuth, :ensure_onboarding_complete},
        {YscWeb.UserAuth, :mount_reauth_session},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings},
        {YscWeb.Plugs.RequestPath, :set_request_path}
      ] do
      get "/pending-review", PageController, :pending_review

      live "/users/settings", UserSettingsLive, :edit

      live "/users/settings/phone-verification",
           UserSettingsLive,
           :phone_verification

      live "/users/settings/email-verification",
           UserSettingsLive,
           :email_verification

      live "/users/settings/security", UserSecurityLive, :index
      live "/users/settings/passkeys/new", PasskeyRegistrationLive, :new
      live "/users/payments", UserSettingsLive, :payments
      live "/users/membership", UserSettingsLive, :membership
      live "/users/membership/payment-method", UserSettingsLive, :payment_method
      live "/users/notifications", UserSettingsLive, :notifications

      live "/users/settings/confirm-email/:token",
           UserSettingsLive,
           :confirm_email

      live "/users/settings/family", FamilyManagementLive, :index
      live "/users/tickets", UserTicketsLive, :index
      live "/tickets/:order_id", UserTicketsLive, :show
      live "/tickets/:order_id/qr", TicketQrLive, :index
      live "/events/:event_id/tickets/qr", TicketQrLive, :event
      live "/orders/:order_id/confirmation", OrderConfirmationLive, :index
      live "/bookings/:id", UserBookingDetailLive, :index
      live "/expensereport", ExpenseReportLive, :index
      live "/expensereports", ExpenseReportLive, :list
      live "/expensereport/:id/success", ExpenseReportLive, :success
      live "/events/photos/:upload_token", EventPhotoUploadLive, :show
    end
  end

  scope "/", YscWeb do
    pipe_through [:browser]

    delete "/users/log-out", UserSessionController, :delete
    post "/users/log-out", UserSessionController, :delete_with_redirect

    live_session :current_user,
      on_mount: [
        {YscWeb.LiveToastMount, :mount_toasts_sync},
        {YscWeb.UserAuth, :mount_current_user},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings},
        {YscWeb.Plugs.RequestPath, :set_request_path}
      ] do
      live "/family-invite/:token/accept", FamilyInviteAcceptanceLive, :index

      live "/family-invite/:token/logout-required",
           FamilyInviteLogoutRequiredLive,
           :index

      live "/payment/success", PaymentSuccessLive, :index
    end
  end

  # Full admin-only routes (not accessible by volunteers)
  scope "/admin", YscWeb do
    pipe_through [
      :admin_browser,
      :require_authenticated_user,
      :require_admin,
      :full_admin_only
    ]

    post "/impersonate/:user_id", ImpersonationController, :impersonate
    post "/stop-impersonation", ImpersonationController, :stop_impersonation

    get "/integrations/google-photos/connect",
        AdminGooglePhotosAuthController,
        :connect

    get "/integrations/google-photos/callback",
        AdminGooglePhotosAuthController,
        :callback

    delete "/integrations/google-photos",
           AdminGooglePhotosAuthController,
           :disconnect

    live_dashboard "/dashboard", metrics: {YscWeb.Telemetry, :metrics}
  end

  scope "/admin", YscWeb do
    pipe_through [:admin_browser, :require_authenticated_user, :require_admin]

    get "/exports/:filename", AdminExportController, :show

    # Handle uploads from editors (accessible to volunteers for content creation)
    post "/trix-uploads", TrixUploadsController, :create

    live_session :require_admin,
      on_mount: [
        {YscWeb.LiveToastMount, :mount_toasts_sync},
        {YscWeb.UserAuth, :ensure_authenticated},
        {YscWeb.UserAuth, :ensure_admin},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings},
        {YscWeb.Plugs.AdminSidebarState, :mount_sidebar_state}
      ] do
      live "/", AdminDashboardLive, :index

      # Handling media gallery
      live "/media", AdminMediaLive, :index
      live "/media/upload", AdminMediaLive, :upload
      live "/media/upload/:id", AdminMediaLive, :edit

      # User management
      live "/users", AdminUsersLive, :index

      # Membership monitoring
      live "/memberships", AdminMembershipsLive, :index
      live "/users/:id", AdminUsersLive, :edit
      live "/users/:id/review", AdminUsersLive, :review
      live "/users/:id/details", AdminUserDetailsLive, :profile
      live "/users/:id/details/orders", AdminUserDetailsLive, :orders
      live "/users/:id/details/bookings", AdminUserDetailsLive, :bookings

      live "/users/:id/details/booking-benefits",
           AdminUserDetailsLive,
           :booking_benefits

      live "/users/:id/details/application", AdminUserDetailsLive, :application
      live "/users/:id/details/membership", AdminUserDetailsLive, :membership

      live "/users/:id/details/notifications",
           AdminUserDetailsLive,
           :notifications

      live "/users/:id/details/bank-accounts",
           AdminUserDetailsLive,
           :bank_accounts

      live "/users/:id/details/family", AdminUserDetailsLive, :family
      live "/users/:id/details/logs", AdminUserDetailsLive, :logs

      # Money
      live "/money", AdminMoneyLive, :index
      live "/money/payments/:id", AdminMoneyLive, :view_payment
      live "/money/payments/:id/refund", AdminMoneyLive, :refund_payment
      live "/money/payouts/:id", AdminMoneyLive, :view_payout

      # Events
      live "/events", AdminEventsLive, :index
      live "/events/new", AdminEventsNewLive, :new
      live "/events/:id/edit", AdminEventsNewLive, :edit
      live "/events/:id/tickets", AdminEventsNewLive, :tickets
      live "/events/:id/updates", AdminEventsNewLive, :updates
      live "/events/:id/statistics", AdminEventsNewLive, :statistics

      get "/events/:id/tv-poster/image", EventTvPosterController, :image
      get "/events/:id/tv-poster", EventTvPosterController, :show

      # Tahoe and Clear Lake settings etc, see bookings
      live "/bookings", AdminBookingsLive, :index

      live "/bookings/entitlements",
           AdminBookingEntitlementsLive,
           :index

      live "/bookings/:id", AdminBookingsLive, :view_booking
      live "/bookings/pricing-rules/new", AdminBookingsLive, :new_pricing_rule

      live "/bookings/pricing-rules/:id/edit",
           AdminBookingsLive,
           :edit_pricing_rule

      live "/bookings/blackouts/new", AdminBookingsLive, :new_blackout
      live "/bookings/blackouts/:id/edit", AdminBookingsLive, :edit_blackout
      live "/bookings/bookings/new", AdminBookingsLive, :new_booking
      live "/bookings/bookings/:id/edit", AdminBookingsLive, :edit_booking
      live "/bookings/seasons/:id/edit", AdminBookingsLive, :edit_season

      live "/bookings/refund-policies/new",
           AdminBookingsLive,
           :new_refund_policy

      live "/bookings/refund-policies/:id/edit",
           AdminBookingsLive,
           :edit_refund_policy

      live "/bookings/refund-policies/:id/rules",
           AdminBookingsLive,
           :manage_refund_policy_rules

      live "/bookings/rooms/new", AdminBookingsLive, :new_room
      live "/bookings/rooms/:id/edit", AdminBookingsLive, :edit_room

      # Admin help (interactive guides)
      live "/help", AdminHelpLive, :index
      live "/help/ghost/:name", AdminHelpGhostLive, :show
      live "/help/*parts", AdminHelpGuideLive, :show

      # News and notices
      live "/posts", AdminPostsLive, :index
      live "/posts/new", AdminPostEditorLive, :new
      live "/posts/:id", AdminPostEditorLive, :edit
      live "/posts/:id/preview", AdminPostEditorLive, :preview
      live "/posts/:id/settings", AdminPostEditorLive, :settings

      # Newsletters
      live "/newsletters", AdminNewslettersLive, :index
      live "/newsletters/new", AdminNewsletterEditorLive, :new
      live "/newsletters/:id/edit", AdminNewsletterEditorLive, :edit

      # Website specific settings (such as socials etc)
      live "/settings", AdminSettingsLive, :index

      # QR Scanner
      live "/scanner", AdminScannerLive, :index
      live "/scanner/sessions", AdminScannerLive, :sessions
      live "/scanner/sessions/:id", AdminScannerLive, :session_detail

      # Event check-in management
      live "/events/:id/check-in", AdminEventCheckInLive, :index

      # Membership check-in desk (event_membership sessions)
      live "/membership-check-in/:session_id",
           AdminMembershipCheckInLive,
           :index
    end
  end

  scope "/billing/user" do
    # make sure to authenticate your users for this route
    pipe_through [:browser, :require_authenticated_user]

    scope "/:user_id" do
      post "/payment-method",
           Ysc.Controllers.StripePaymentMethodController,
           :store_payment_method

      get "/finalize", Ysc.Controllers.StripePaymentMethodController, :finalize

      get "/setup-payment",
          Ysc.Controllers.StripePaymentMethodController,
          :setup_payment
    end
  end

  # Webhook endpoints (no CSRF protection needed)
  scope "/webhooks", YscWeb do
    pipe_through [:api]

    post "/quickbooks", QuickbooksWebhookController, :webhook
    post "/ses", SesWebhookController, :webhook
  end
end
