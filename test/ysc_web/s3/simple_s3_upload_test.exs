defmodule YscWeb.S3.SimpleS3UploadTest do
  use ExUnit.Case, async: true

  alias YscWeb.S3.SimpleS3Upload

  @config %{
    region: "us-east-1",
    access_key_id: "AKIAIOSFODNN7EXAMPLE",
    secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  }

  @bucket "test-bucket"

  describe "sign_form_upload/3" do
    test "returns ok tuple with form fields" do
      opts = [
        key: "public/test-file.jpg",
        content_type: "image/jpeg",
        max_file_size: 10_000_000,
        expires_in: 3_600_000
      ]

      assert {:ok, fields} =
               SimpleS3Upload.sign_form_upload(@config, @bucket, opts)

      assert is_map(fields)
      assert fields["key"] == "public/test-file.jpg"
      assert fields["acl"] == "public-read"
      assert fields["content-type"] == "image/jpeg"
      assert fields["x-amz-server-side-encryption"] == "AES256"
      assert fields["x-amz-algorithm"] == "AWS4-HMAC-SHA256"
    end

    test "includes all required form fields" do
      opts = [
        key: "public/test-file.jpg",
        content_type: "image/jpeg",
        max_file_size: 10_000_000,
        expires_in: 3_600_000
      ]

      {:ok, fields} = SimpleS3Upload.sign_form_upload(@config, @bucket, opts)

      required_fields = [
        "key",
        "acl",
        "content-type",
        "x-amz-server-side-encryption",
        "x-amz-credential",
        "x-amz-algorithm",
        "x-amz-date",
        "policy",
        "x-amz-signature"
      ]

      Enum.each(required_fields, fn field ->
        assert Map.has_key?(fields, field), "Missing required field: #{field}"
        assert is_binary(fields[field]), "Field #{field} should be a string"
      end)
    end

    test "generates valid policy" do
      opts = [
        key: "public/test-file.jpg",
        content_type: "image/jpeg",
        max_file_size: 10_000_000,
        expires_in: 3_600_000
      ]

      {:ok, fields} = SimpleS3Upload.sign_form_upload(@config, @bucket, opts)

      # Policy should be base64 encoded
      assert is_binary(fields["policy"])

      # Decode and verify policy structure
      policy_json = Base.decode64!(fields["policy"])
      policy = Jason.decode!(policy_json)

      assert Map.has_key?(policy, "expiration")
      assert Map.has_key?(policy, "conditions")
      assert is_list(policy["conditions"])

      # Verify conditions contain expected values
      conditions = policy["conditions"]
      assert %{"bucket" => @bucket} in conditions
      assert ["eq", "$key", "public/test-file.jpg"] in conditions
      assert %{"acl" => "public-read"} in conditions
      assert ["eq", "$Content-Type", "image/jpeg"] in conditions
      assert ["content-length-range", 0, 10_000_000] in conditions
    end

    test "generates valid signature" do
      opts = [
        key: "public/test-file.jpg",
        content_type: "image/jpeg",
        max_file_size: 10_000_000,
        expires_in: 3_600_000
      ]

      {:ok, fields} = SimpleS3Upload.sign_form_upload(@config, @bucket, opts)

      # Signature should be a hex string
      signature = fields["x-amz-signature"]
      assert is_binary(signature)
      assert String.length(signature) == 64
      assert Regex.match?(~r/^[0-9a-f]{64}$/, signature)
    end

    test "generates credential in correct format" do
      opts = [
        key: "public/test-file.jpg",
        content_type: "image/jpeg",
        max_file_size: 10_000_000,
        expires_in: 3_600_000
      ]

      {:ok, fields} = SimpleS3Upload.sign_form_upload(@config, @bucket, opts)

      credential = fields["x-amz-credential"]
      assert is_binary(credential)
      # Format: access_key_id/YYYYMMDD/region/s3/aws4_request
      parts = String.split(credential, "/")
      assert length(parts) == 5
      assert Enum.at(parts, 0) == @config.access_key_id
      assert Enum.at(parts, 2) == @config.region
      assert Enum.at(parts, 3) == "s3"
      assert Enum.at(parts, 4) == "aws4_request"
    end

    test "generates amz_date in correct format" do
      opts = [
        key: "public/test-file.jpg",
        content_type: "image/jpeg",
        max_file_size: 10_000_000,
        expires_in: 3_600_000
      ]

      {:ok, fields} = SimpleS3Upload.sign_form_upload(@config, @bucket, opts)

      amz_date = fields["x-amz-date"]
      assert is_binary(amz_date)
      # Format: YYYYMMDDTHHMMSSZ
      assert String.length(amz_date) == 16
      assert String.ends_with?(amz_date, "Z")
      assert Regex.match?(~r/^\d{8}T\d{6}Z$/, amz_date)
    end

    test "handles different content types" do
      content_types = ["image/png", "application/pdf", "text/plain"]

      Enum.each(content_types, fn content_type ->
        opts = [
          key: "public/test-file",
          content_type: content_type,
          max_file_size: 10_000_000,
          expires_in: 3_600_000
        ]

        assert {:ok, fields} =
                 SimpleS3Upload.sign_form_upload(@config, @bucket, opts)

        assert fields["content-type"] == content_type
      end)
    end

    test "handles different file sizes" do
      file_sizes = [1_000, 1_000_000, 100_000_000]

      Enum.each(file_sizes, fn max_file_size ->
        opts = [
          key: "public/test-file.jpg",
          content_type: "image/jpeg",
          max_file_size: max_file_size,
          expires_in: 3_600_000
        ]

        assert {:ok, fields} =
                 SimpleS3Upload.sign_form_upload(@config, @bucket, opts)

        # Verify the policy includes the correct max file size
        policy_json = Base.decode64!(fields["policy"])
        policy = Jason.decode!(policy_json)
        conditions = policy["conditions"]

        assert ["content-length-range", 0, max_file_size] in conditions
      end)
    end

    test "handles different expiration times" do
      expiration_times = [1000, 3_600_000, 86_400_000]

      Enum.each(expiration_times, fn expires_in ->
        opts = [
          key: "public/test-file.jpg",
          content_type: "image/jpeg",
          max_file_size: 10_000_000,
          expires_in: expires_in
        ]

        assert {:ok, fields} =
                 SimpleS3Upload.sign_form_upload(@config, @bucket, opts)

        # Verify expiration is set in the future
        policy_json = Base.decode64!(fields["policy"])
        policy = Jason.decode!(policy_json)
        expiration = policy["expiration"]

        {:ok, expiration_dt, _} = DateTime.from_iso8601(expiration)
        now = DateTime.utc_now()

        assert DateTime.compare(expiration_dt, now) == :gt
      end)
    end

    test "works with Tigris region 'auto'" do
      tigris_config = %{
        region: "auto",
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
      }

      opts = [
        key: "public/test-file.jpg",
        content_type: "image/jpeg",
        max_file_size: 10_000_000,
        expires_in: 3_600_000
      ]

      assert {:ok, fields} =
               SimpleS3Upload.sign_form_upload(tigris_config, @bucket, opts)

      assert fields["x-amz-credential"] =~ "auto"
    end

    test "generates consistent signature for same inputs" do
      opts = [
        key: "public/test-file.jpg",
        content_type: "image/jpeg",
        max_file_size: 10_000_000,
        expires_in: 3_600_000
      ]

      # Note: Due to timestamp in policy, signatures will differ
      # But we can verify the structure is consistent
      {:ok, fields1} = SimpleS3Upload.sign_form_upload(@config, @bucket, opts)
      {:ok, fields2} = SimpleS3Upload.sign_form_upload(@config, @bucket, opts)

      # Key fields should be the same
      assert fields1["key"] == fields2["key"]
      assert fields1["acl"] == fields2["acl"]
      assert fields1["content-type"] == fields2["content-type"]
    end

    test "raises error when required option is missing" do
      # Missing :key
      assert_raise KeyError, fn ->
        SimpleS3Upload.sign_form_upload(@config, @bucket,
          content_type: "image/jpeg",
          max_file_size: 10_000_000,
          expires_in: 3_600_000
        )
      end

      # Missing :content_type
      assert_raise KeyError, fn ->
        SimpleS3Upload.sign_form_upload(@config, @bucket,
          key: "public/test-file.jpg",
          max_file_size: 10_000_000,
          expires_in: 3_600_000
        )
      end

      # Missing :max_file_size
      assert_raise KeyError, fn ->
        SimpleS3Upload.sign_form_upload(@config, @bucket,
          key: "public/test-file.jpg",
          content_type: "image/jpeg",
          expires_in: 3_600_000
        )
      end

      # Missing :expires_in
      assert_raise KeyError, fn ->
        SimpleS3Upload.sign_form_upload(@config, @bucket,
          key: "public/test-file.jpg",
          content_type: "image/jpeg",
          max_file_size: 10_000_000
        )
      end
    end
  end
end
