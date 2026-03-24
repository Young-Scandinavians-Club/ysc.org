import EctoEnum

defenum(ScanSessionType, ["membership", "event"])
defenum(CheckinType, ["individual", "group"])

defenum(ScanResultType, [
  "success",
  "already_scanned",
  "invalid",
  "expired",
  "cross_mode",
  "rate_limited"
])
