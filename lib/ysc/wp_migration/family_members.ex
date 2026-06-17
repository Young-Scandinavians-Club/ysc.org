defmodule Ysc.WpMigration.FamilyMembers do
  @moduledoc """
  Builds and syncs `FamilyMember` records from WordPress migration application rows.

  Application export data (`applications.json`) may include:

  - `spouse_first_name` / `spouse_last_name`
  - `children` — list of `%{"name" => ..., "birthday" => ...}` (up to four from WP)
  """

  require Ysc.Logging
  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.Accounts.FamilyMember
  alias Ysc.Ci.QueryExplain.Fixtures

  @type application_row :: map()
  @type member_attrs :: %{
          required(:first_name) => String.t(),
          required(:last_name) => String.t(),
          required(:type) => :spouse | :child,
          optional(:birth_date) => Date.t() | nil
        }

  @type sync_stats :: %{
          inserted: non_neg_integer(),
          updated: non_neg_integer(),
          skipped: non_neg_integer()
        }

  @doc """
  Returns normalised family member attribute maps from a migration application row.
  Invalid or empty entries are dropped.
  """
  def build_records(%{} = row) do
    spouse_records(row) ++ child_records(row)
  end

  def build_records(_), do: []

  @doc """
  Upserts family members for `user_id` from an application export row.

  Matches existing records by `type` and normalised name so re-running the loader
  is idempotent. Returns `{:ok, stats}`.
  """
  def sync_for_user(user_id, %{} = row) when is_binary(user_id) do
    desired = build_records(row)

    existing =
      FamilyMember
      |> where(user_id: ^user_id)
      |> Repo.all()

    {stats, _existing} =
      Enum.reduce(
        desired,
        {%{inserted: 0, updated: 0, skipped: 0}, existing},
        fn attrs, {acc, existing_acc} ->
          case upsert_member(user_id, existing_acc, attrs) do
            {:inserted, member} ->
              {%{acc | inserted: acc.inserted + 1}, [member | existing_acc]}

            {:updated, _} ->
              {%{acc | updated: acc.updated + 1}, existing_acc}

            :skipped ->
              {%{acc | skipped: acc.skipped + 1}, existing_acc}
          end
        end
      )

    {:ok, stats}
  end

  @doc false
  def ci_query_explain_query do
    user = Fixtures.user()

    FamilyMember
    |> where(user_id: ^user.id)
  end

  @doc """
  Splits a full name into `{first_name, last_name}`.

  WordPress child name fields are often a single full name string. The last
  whitespace-separated token becomes the last name; a single token uses `"-"`
  as the last name placeholder (required by our schema).
  """
  def split_name(name) when is_binary(name) do
    name = String.trim(name)

    parts =
      name
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reject(&(&1 == ""))

    case parts do
      [] ->
        nil

      [only] ->
        {only, "-"}

      _ ->
        {Enum.join(Enum.drop(parts, -1), " "), List.last(parts)}
    end
  end

  def split_name(_), do: nil

  @doc """
  Parses a WordPress child birthday value into a `Date`.

  Supports ISO dates, US `M/D/YYYY`, and bare four-digit years (stored as Jan 1).
  """
  def parse_birth_date(nil), do: nil
  def parse_birth_date(""), do: nil
  def parse_birth_date("0"), do: nil

  def parse_birth_date(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      Regex.match?(~r/^\d{4}$/, value) ->
        year = String.to_integer(value)
        if year >= 1900, do: Date.new!(year, 1, 1), else: nil

      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value) ->
        case Date.from_iso8601(value) do
          {:ok, date} -> date
          _ -> nil
        end

      Regex.match?(~r/^\d{1,2}\/\d{1,2}\/\d{4}$/, value) ->
        parse_us_slash_date(value)

      Regex.match?(~r/^\d{4}[-\/]\d{2}[-\/]\d{2}/, value) ->
        value
        |> String.slice(0, 10)
        |> String.replace("/", "-")
        |> then(fn iso ->
          case Date.from_iso8601(iso) do
            {:ok, date} -> date
            _ -> nil
          end
        end)

      true ->
        nil
    end
  end

  def parse_birth_date(_), do: nil

  defp parse_us_slash_date(value) when is_binary(value) do
    case String.split(value, "/") do
      [month_str, day_str, year_str] ->
        with {month, ""} <- Integer.parse(month_str),
             {day, ""} <- Integer.parse(day_str),
             {year, ""} <- Integer.parse(year_str),
             {:ok, date} <- Date.new(year, month, day) do
          date
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp spouse_records(row) do
    first = presence(row["spouse_first_name"])
    last = presence(row["spouse_last_name"])

    cond do
      first && last ->
        [spouse_attrs(first, last)]

      first ->
        case split_name(first) do
          {f, l} -> [spouse_attrs(f, l)]
          nil -> []
        end

      last ->
        [spouse_attrs("-", last)]

      true ->
        []
    end
  end

  defp spouse_attrs(first_name, last_name) do
    %{
      first_name: first_name,
      last_name: last_name,
      type: :spouse,
      birth_date: nil
    }
  end

  defp child_records(row) do
    row
    |> Map.get("children", [])
    |> List.wrap()
    |> Enum.flat_map(&child_attrs/1)
  end

  defp child_attrs(%{"name" => name} = child) when is_binary(name) do
    case split_name(name) do
      {first_name, last_name} ->
        birth_date = parse_birth_date(child["birthday"])

        [
          %{
            first_name: first_name,
            last_name: last_name,
            type: :child,
            birth_date: birth_date
          }
        ]

      nil ->
        []
    end
  end

  defp child_attrs(_), do: []

  defp upsert_member(user_id, existing, attrs) do
    case find_existing(existing, attrs) do
      %FamilyMember{} = member ->
        changes =
          %{}
          |> maybe_put_change(:first_name, member.first_name, attrs.first_name)
          |> maybe_put_change(:last_name, member.last_name, attrs.last_name)
          |> maybe_put_change(:birth_date, member.birth_date, attrs.birth_date)

        if changes == %{} do
          :skipped
        else
          member
          |> FamilyMember.family_member_changeset(changes)
          |> Repo.update()
          |> case do
            {:ok, _} ->
              {:updated, member}

            {:error, changeset} ->
              log_failure(user_id, attrs, changeset)
              :skipped
          end
        end

      nil ->
        %FamilyMember{}
        |> FamilyMember.family_member_changeset(Map.put(attrs, :email, nil))
        |> Ecto.Changeset.put_change(:user_id, user_id)
        |> Repo.insert()
        |> case do
          {:ok, member} ->
            {:inserted, member}

          {:error, changeset} ->
            log_failure(user_id, attrs, changeset)
            :skipped
        end
    end
  end

  defp find_existing(existing, %{type: :spouse} = attrs) do
    Enum.find(existing, fn m ->
      m.type == :spouse && names_match?(m, attrs)
    end) || Enum.find(existing, &(&1.type == :spouse))
  end

  defp find_existing(existing, %{type: :child} = attrs) do
    Enum.find(existing, fn m ->
      m.type == :child && names_match?(m, attrs)
    end)
  end

  defp names_match?(member, attrs) do
    norm(member.first_name) == norm(attrs.first_name) &&
      norm(member.last_name) == norm(attrs.last_name)
  end

  defp norm(nil), do: ""

  defp norm(value) when is_binary(value),
    do: String.downcase(String.trim(value))

  defp norm(value), do: value |> to_string() |> norm()

  defp maybe_put_change(changes, field, current, desired) do
    if is_nil(desired) or current == desired do
      changes
    else
      Map.put(changes, field, desired)
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil

  defp presence(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp presence(value), do: value

  defp log_failure(user_id, attrs, changeset) do
    Ysc.Logging.warning(
      "[WP Load] Failed to sync family member",
      user_id: user_id,
      attrs: attrs,
      errors: inspect(changeset.errors)
    )
  end
end
