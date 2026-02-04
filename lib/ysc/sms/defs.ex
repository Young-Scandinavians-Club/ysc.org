import EctoEnum

defenum(SmsProvider, ["flowroute"])

# Status for outbound SMS messages
defenum(SmsMessageStatus, ["sent", "buffered", "delivered", "failed"])

# Status for inbound SMS messages (from provider webhook)
defenum(SmsReceivedStatus, ["delivered", "failed", "pending"])

# Status for delivery receipts (DLRs)
defenum(SmsDeliveryReceiptStatus, [
  "delivered",
  "failed",
  "message_buffered",
  "message_sent",
  "pending"
])

# Direction for SMS messages
defenum(SmsDirection, ["inbound", "outbound"])
