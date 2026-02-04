import EctoEnum

defenum(UserAccountState, [
  "pending_approval",
  "rejected",
  "active",
  "suspended",
  "deleted"
])

defenum(UserAccountRole, ["member", "admin"])
defenum(FamilyMemberType, ["spouse", "child"])
defenum(MembershipType, ["single", "family"])

defenum(BoardMemberPosition, [
  "president",
  "vice_president",
  "secretary",
  "treasurer",
  "clear_lake_cabin_master",
  "tahoe_cabin_master",
  "event_director",
  "member_outreach",
  "membership_director"
])

defenum(MembershipEligibility, [
  "citizen_of_scandinavia",
  "born_in_scandinavia",
  "scandinavian_parent",
  "lived_in_scandinavia",
  "speak_scandinavian_language",
  "spouse_of_member"
])

defenum(SignupApplicationEventType, [
  "review_started",
  "review_completed",
  "review_updated"
])

defenum(UserApplicationReviewOutcome, ["approved", "rejected"])

defenum(UserEventType, [
  "state_update",
  "role_update",
  "family_added",
  "family_removed"
])

defenum(UserNoteCategory, ["general", "violation"])
