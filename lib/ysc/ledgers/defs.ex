import EctoEnum

defenum(LedgerAccountType, [
  "revenue",
  "liability",
  "expense",
  "asset",
  "equity"
])

defenum(LedgerNormalBalance, ["debit", "credit"])
defenum(LedgerEntryDebitCredit, ["debit", "credit"])

defenum(LedgerEntryEntityType, [
  "event",
  "membership",
  "booking",
  "donation",
  "administration"
])

defenum(LedgerPaymentStatus, ["pending", "completed", "failed", "refunded"])

defenum(LedgerTransactionType, [
  "payment",
  "refund",
  "fee",
  "adjustment",
  "payout"
])

defenum(LedgerTransactionStatus, ["pending", "completed", "reversed"])
defenum(LedgerPaymentProvider, ["stripe"])
