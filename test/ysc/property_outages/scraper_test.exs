defmodule Ysc.PropertyOutages.ScraperTest do
  @moduledoc """
  Unit tests for Optimum/Kubra URL construction.

  The live scrape hits Kubra.io; these tests cover the rotating-dataset
  URL builder added after a hardcoded snapshot URL 404'd and silently
  skipped Tahoe internet-outage detection (#1105).
  """
  use ExUnit.Case, async: true

  alias Ysc.PropertyOutages.Scraper

  # Stable quadkey identifiers for 2685 Cedar Lane, Homewood, CA 96141
  @tahoe_quadkey_bucket "300"
  @tahoe_quadkey_filename "02301012302231003"

  describe "optimum_cluster_data_url/1" do
    test "substitutes the Tahoe cabin quadkey bucket into the Kubra template" do
      url =
        Scraper.optimum_cluster_data_url(
          "stormcenter/datasets/ROTATING-DATASET-ID/{qkh}"
        )

      assert url ==
               "https://kubra.io/stormcenter/datasets/ROTATING-DATASET-ID/#{@tahoe_quadkey_bucket}/public/cluster-2/#{@tahoe_quadkey_filename}.json"
    end

    test "keeps the rotating dataset id from currentState instead of a hardcoded snapshot" do
      dataset_id = "a1b2c3d4-current-cycle"
      template = "kubra/#{dataset_id}/clusterdata/{qkh}"

      url = Scraper.optimum_cluster_data_url(template)

      assert url =~ dataset_id
      assert url =~ "/#{@tahoe_quadkey_bucket}/"
      assert String.ends_with?(url, "/#{@tahoe_quadkey_filename}.json")
      refute url =~ "{qkh}"
    end

    test "still builds a cluster URL when the template has no {qkh} placeholder" do
      url = Scraper.optimum_cluster_data_url("already/resolved/path")

      assert url ==
               "https://kubra.io/already/resolved/path/public/cluster-2/#{@tahoe_quadkey_filename}.json"
    end
  end
end
