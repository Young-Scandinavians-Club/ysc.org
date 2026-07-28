defmodule YscWeb.Workers.EmailNotifierQueueTest do
  use ExUnit.Case, async: true

  alias YscWeb.Workers.EmailNotifier

  test "routes member-facing transactional email ahead of bulk notifications" do
    assert EmailNotifier.queue_for_category(:account) == :transactional_mail
    assert EmailNotifier.queue_for_category("account") == :transactional_mail
    assert EmailNotifier.queue_for_category(:event) == :bulk_mail
    assert EmailNotifier.queue_for_category(:newsletter) == :bulk_mail
  end
end
