Mox.defmock(Stripe.CustomerMock, for: Stripe.CustomerBehaviour)
Mox.defmock(Ysc.AccountsMock, for: Ysc.Accounts.Behaviour)
Mox.defmock(Ysc.Quickbooks.ClientMock, for: Ysc.Quickbooks.ClientBehaviour)
Mox.defmock(Ysc.StripeMock, for: Ysc.StripeBehaviour)
Mox.defmock(Ysc.KeilaMock, for: Ysc.Keila.Behaviour)

# Stripe API mocks for controller testing
Mox.defmock(Stripe.PaymentMethodMock, for: Ysc.Stripe.PaymentMethodBehaviour)
Mox.defmock(Stripe.SetupIntentMock, for: Ysc.Stripe.SetupIntentBehaviour)
Mox.defmock(Stripe.PaymentIntentMock, for: Ysc.Stripe.PaymentIntentBehaviour)

# Internal service mocks for controller testing
Mox.defmock(Ysc.CustomersMock, for: Ysc.Customers.Behaviour)
Mox.defmock(Ysc.PaymentsMock, for: Ysc.Payments.Behaviour)
