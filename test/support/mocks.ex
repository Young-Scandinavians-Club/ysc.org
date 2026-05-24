Mox.defmock(Stripe.CustomerMock, for: Stripe.CustomerBehaviour)
Mox.defmock(Stripe.SubscriptionMock, for: Stripe.SubscriptionBehaviour)
Mox.defmock(Ysc.AccountsMock, for: Ysc.Accounts.Behaviour)
Mox.defmock(Ysc.Quickbooks.ClientMock, for: Ysc.Quickbooks.ClientBehaviour)
Mox.defmock(Ysc.StripeMock, for: Ysc.StripeBehaviour)

# Stripe API mocks for controller testing
Mox.defmock(Stripe.PaymentMethodMock, for: Ysc.Stripe.PaymentMethodBehaviour)
Mox.defmock(Stripe.PaymentIntentMock, for: Ysc.Stripe.PaymentIntentBehaviour)
Mox.defmock(Stripe.InvoiceMock, for: Ysc.Stripe.InvoiceBehaviour)

# Discord HTTP mock to avoid real network calls in tests
Mox.defmock(Ysc.Alerts.DiscordHttpMock, for: Ysc.Alerts.DiscordHttpBehaviour)

# Turnstile mock to avoid real Cloudflare API calls in tests
Mox.defmock(TurnstileMock, for: Turnstile.Behaviour)

# Internal service mocks for controller testing
Mox.defmock(Ysc.CustomersMock, for: Ysc.Customers.Behaviour)
Mox.defmock(Ysc.PaymentsMock, for: Ysc.Payments.Behaviour)
