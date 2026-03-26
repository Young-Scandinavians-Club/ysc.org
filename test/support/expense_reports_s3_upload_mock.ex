defmodule Ysc.ExpenseReports.S3UploadMock do
  @moduledoc """
  Mock S3 upload for tests. Returns the given key without calling ExAws.
  """
  def upload(_path, _bucket_name, unique_key) do
    # Return a result shape that matches what ExAws.request! returns
    # so ExpenseReports can use result[:body][:key] || unique_key
    %{body: %{key: unique_key}}
  end
end

defmodule Ysc.ExpenseReports.S3UploadMockEmptyBodyKey do
  @moduledoc false
  def upload(_path, _bucket_name, _unique_key), do: %{body: %{}}
end
