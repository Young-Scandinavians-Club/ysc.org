defmodule Ysc.GeoIP.DatabaseFetcherTest do
  use ExUnit.Case, async: false

  alias Ysc.GeoIP.DatabaseFetcher
  alias Ysc.S3Config

  setup do
    original_get = Application.get_env(:ysc, :geo_ip_s3_get)

    on_exit(fn ->
      if original_get do
        Application.put_env(:ysc, :geo_ip_s3_get, original_get)
      else
        Application.delete_env(:ysc, :geo_ip_s3_get)
      end
    end)

    :ok
  end

  describe "description/1" do
    test "reports a remote S3 source" do
      assert %{
               database_is_stored_remotely: true,
               database_is_fetched_from: {:s3, bucket, key}
             } = DatabaseFetcher.description([])

      assert bucket == S3Config.app_resources_bucket_name()
      assert key == DatabaseFetcher.object_key()
    end
  end

  describe "fetch/1" do
    test "returns a tgz success when S3 returns the object" do
      modified = {{2026, 7, 28}, {10, 0, 0}}

      Application.put_env(:ysc, :geo_ip_s3_get, fn ->
        {:ok, "fake-tarball-bytes", modified}
      end)

      assert {:fetched,
              %{
                format: :tgz,
                content: "fake-tarball-bytes",
                metadata: %{
                  fetched_from: {:s3, bucket, key},
                  modified_on: ^modified
                }
              }} = DatabaseFetcher.fetch([])

      assert bucket == S3Config.app_resources_bucket_name()
      assert key == DatabaseFetcher.object_key()
    end

    test "returns an error when the object is missing" do
      Application.put_env(:ysc, :geo_ip_s3_get, fn ->
        {:error, {:http_error, 404, %{}}}
      end)

      assert {:error, {:http_error, 404, %{}}} = DatabaseFetcher.fetch([])
    end

    test "returns an error when the S3 request fails" do
      Application.put_env(:ysc, :geo_ip_s3_get, fn ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = DatabaseFetcher.fetch([])
    end
  end

  describe "conditionally_fetch/2" do
    test "dismisses when modified_on matches the previous fetch" do
      modified = {{2026, 7, 28}, {10, 0, 0}}

      Application.put_env(:ysc, :geo_ip_s3_get, fn ->
        {:ok, "fake-tarball-bytes", modified}
      end)

      assert :dismissed =
               DatabaseFetcher.conditionally_fetch(
                 [],
                 {:depending_on, %{fetched_from: :s3, modified_on: modified}}
               )
    end

    test "returns fetched when modified_on changed" do
      previous = {{2026, 7, 1}, {0, 0, 0}}
      current = {{2026, 7, 28}, {10, 0, 0}}

      Application.put_env(:ysc, :geo_ip_s3_get, fn ->
        {:ok, "newer-bytes", current}
      end)

      assert {:fetched,
              %{content: "newer-bytes", metadata: %{modified_on: ^current}}} =
               DatabaseFetcher.conditionally_fetch(
                 [],
                 {:depending_on, %{fetched_from: :s3, modified_on: previous}}
               )
    end

    test "propagates fetch errors" do
      Application.put_env(:ysc, :geo_ip_s3_get, fn ->
        {:error, :econnrefused}
      end)

      assert {:error, :econnrefused} =
               DatabaseFetcher.conditionally_fetch(
                 [],
                 {:depending_on,
                  %{fetched_from: :s3, modified_on: {{2026, 1, 1}, {0, 0, 0}}}}
               )
    end
  end

  describe "request_from_s3/0 (real path, no :geo_ip_s3_get override)" do
    test "fetches via a presigned URL against real S3" do
      bucket = S3Config.app_resources_bucket_name()
      key = DatabaseFetcher.object_key()

      bucket
      |> ExAws.S3.put_object(key, "real-tarball-bytes")
      |> ExAws.request!()

      on_exit(fn ->
        bucket |> ExAws.S3.delete_object(key) |> ExAws.request()
      end)

      assert {:fetched, %{format: :tgz, content: "real-tarball-bytes"}} =
               DatabaseFetcher.fetch([])
    end

    test "returns an error when the object doesn't exist" do
      bucket = S3Config.app_resources_bucket_name()
      key = DatabaseFetcher.object_key()

      # Make sure nothing is left over from a previous run.
      bucket |> ExAws.S3.delete_object(key) |> ExAws.request()

      assert {:error, _reason} = DatabaseFetcher.fetch([])
    end

    test "returns an error when the S3 host is unreachable" do
      original = Application.get_env(:ex_aws, :s3)

      # Port 1 is a privileged port nothing listens on locally, so Req.get
      # fails at the transport level -- exercising request_from_s3/0's
      # {:error, reason} branch (as opposed to a non-200 HTTP response).
      Application.put_env(:ex_aws, :s3, Keyword.put(original, :port, 1))

      try do
        assert {:error, _reason} = DatabaseFetcher.fetch([])
      after
        Application.put_env(:ex_aws, :s3, original)
      end
    end
  end

  describe "failure resilience" do
    test "fetch/1 returns error when the S3 getter raises" do
      Application.put_env(:ysc, :geo_ip_s3_get, fn ->
        raise "s3 exploded"
      end)

      assert {:error, {:exception, message}} = DatabaseFetcher.fetch([])
      assert message =~ "s3 exploded"
    end

    test "fetch/1 returns error when the S3 getter throws" do
      Application.put_env(:ysc, :geo_ip_s3_get, fn ->
        throw(:boom)
      end)

      assert {:error, {:throw, :boom}} = DatabaseFetcher.fetch([])
    end

    test "conditionally_fetch/2 returns error when the S3 getter raises" do
      Application.put_env(:ysc, :geo_ip_s3_get, fn ->
        raise "conditional boom"
      end)

      assert {:error, {:exception, message}} =
               DatabaseFetcher.conditionally_fetch(
                 [],
                 {:depending_on,
                  %{fetched_from: :s3, modified_on: {{2026, 1, 1}, {0, 0, 0}}}}
               )

      assert message =~ "conditional boom"
    end

    test "fetch/1 returns error for unexpected getter return values" do
      Application.put_env(:ysc, :geo_ip_s3_get, fn -> :not_a_result end)

      assert {:error, {:unexpected_s3_get_result, :not_a_result}} =
               DatabaseFetcher.fetch([])
    end
  end
end
