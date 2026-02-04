defmodule Ysc.ReferenceGeneratorTest do
  use ExUnit.Case
  alias Ysc.ReferenceGenerator

  describe "generate_reference_id/1" do
    test "generates valid reference IDs for valid prefixes" do
      for prefix <- ~w(PMT TKT BKG DON) do
        reference_id = ReferenceGenerator.generate_reference_id(prefix)
        assert :ok = ReferenceGenerator.validate_reference_id(reference_id)
        assert String.starts_with?(reference_id, prefix)
      end
    end

    test "follows the correct format pattern" do
      reference_id = ReferenceGenerator.generate_reference_id("PMT")
      assert Regex.match?(~r/^PMT-\d{6}-[A-Z2-9]{4}[A-Z0-9]$/, reference_id)
    end

    test "raises ArgumentError for invalid prefix" do
      assert_raise ArgumentError, "Invalid prefix: INV", fn ->
        ReferenceGenerator.generate_reference_id("INV")
      end
    end
  end

  describe "validate_reference_id/1" do
    test "accepts valid reference IDs" do
      valid_id = ReferenceGenerator.generate_reference_id("PMT")
      assert :ok = ReferenceGenerator.validate_reference_id(valid_id)
    end

    test "rejects invalid format" do
      assert {:error, "Invalid format"} =
               ReferenceGenerator.validate_reference_id("INVALID")

      assert {:error, "Invalid format"} =
               ReferenceGenerator.validate_reference_id("PMT-12345-ABC")

      assert {:error, "Invalid format"} =
               ReferenceGenerator.validate_reference_id("PMT-123456-ABCDEF")
    end

    test "rejects invalid prefix" do
      assert {:error, "Invalid prefix"} =
               ReferenceGenerator.validate_reference_id("INV-230415-ABC2D")
    end

    test "rejects invalid date format" do
      assert {:error, "Invalid format"} =
               ReferenceGenerator.validate_reference_id("PMT-23041X-ABC2D")
    end

    test "rejects invalid random part" do
      assert {:error, "Invalid random part"} =
               ReferenceGenerator.validate_reference_id("PMT-230415-0IO1D")
    end

    test "rejects invalid checksum" do
      # Generate a valid ID and modify the checksum
      valid_id = ReferenceGenerator.generate_reference_id("PMT")

      # Extract the base parts to compute what the checksum should be
      [_, _prefix, _date, _random_part, correct_checksum] =
        Regex.run(~r/^([A-Z]{3})-(\d{6})-([A-Z0-9]{4})([A-Z0-9])$/, valid_id)

      # Find a character that's guaranteed to be different from the correct checksum
      # Valid checksum characters are: 2-9, A-Z (excluding O and I)
      # We'll try characters in order until we find one that's different
      invalid_checksum =
        [
          "2",
          "3",
          "4",
          "5",
          "6",
          "7",
          "8",
          "9",
          "A",
          "B",
          "C",
          "D",
          "E",
          "F",
          "G",
          "H",
          "J",
          "K",
          "L",
          "M",
          "N",
          "P",
          "Q",
          "R",
          "S",
          "T",
          "U",
          "V",
          "W",
          "X",
          "Y",
          "Z"
        ]
        |> Enum.find(fn char -> char != correct_checksum end)

      invalid_id = String.slice(valid_id, 0..-2//1) <> invalid_checksum

      assert {:error, "Checksum validation failed"} =
               ReferenceGenerator.validate_reference_id(invalid_id)
    end
  end

  describe "compute_checksum/1" do
    test "computes consistent checksums" do
      base = "PMT230415ABC2"
      checksum = ReferenceGenerator.compute_checksum(base)
      assert is_binary(checksum)
      assert String.length(checksum) == 1
      assert Regex.match?(~r/^[A-Z0-9]$/, checksum)

      # Same input should produce same checksum
      assert checksum == ReferenceGenerator.compute_checksum(base)
    end

    test "produces different checksums for different inputs" do
      checksum1 = ReferenceGenerator.compute_checksum("PMT230415ABC2")
      checksum2 = ReferenceGenerator.compute_checksum("PMT230415ABC3")
      assert checksum1 != checksum2
    end
  end
end
