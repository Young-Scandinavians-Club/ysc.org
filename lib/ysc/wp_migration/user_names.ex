defmodule Ysc.WpMigration.UserNames do
  @moduledoc """
  Resolves first and last names for WordPress migration user rows.

  WordPress usermeta often omits `last_name` (or both names). We fall back to the
  signup application, `display_name`, and parts of the email address before using
  a placeholder last name.
  """

  alias Ysc.WpMigration.FamilyMembers

  @type row :: map()

  @doc """
  Returns `%{first_name: ..., last_name: ...}` with non-empty strings suitable
  for `User.registration_changeset/3`.
  """
  def resolve(user_row, application_row \\ %{}) do
    first_name = resolve_first_name(user_row, application_row)
    last_name = resolve_last_name(user_row, application_row, first_name)

    %{
      first_name: first_name,
      last_name: last_name
    }
  end

  defp resolve_first_name(user_row, application_row) do
    user_row
    |> first_name_candidates(application_row)
    |> Enum.find_value(&presence/1)
    |> Kernel.||("Unknown")
  end

  defp resolve_last_name(user_row, application_row, first_name) do
    user_row
    |> last_name_candidates(application_row, first_name)
    |> Enum.find_value(&presence/1)
    |> Kernel.||("-")
  end

  defp first_name_candidates(user_row, application_row) do
    email = user_row["email"]
    display_name = user_row["display_name"]

    [
      user_row["first_name"],
      application_row["first_name"],
      name_from_email_local(email, :first),
      first_from_camel_display(display_name, email),
      name_from_display(display_name, email),
      titleize(email_local_part(email))
    ]
  end

  defp last_name_candidates(user_row, application_row, first_name) do
    email = user_row["email"]
    display_name = user_row["display_name"]

    [
      user_row["last_name"],
      application_row["last_name"],
      last_from_display(display_name, email),
      name_from_email_local(email, :last),
      last_from_first_name_prefix(email, first_name, user_row, application_row),
      last_from_camel_display(display_name, email),
      last_from_email_domain(email)
    ]
  end

  defp first_from_camel_display(display_name, email) do
    if name_like_display?(display_name, email) and camel_case?(display_name) do
      case split_camel_case(display_name) do
        {first, _} -> titleize(first)
        _ -> nil
      end
    end
  end

  defp name_from_display(display_name, email) do
    if name_like_display?(display_name, email) and
         not flattened_email_local?(display_name, email) do
      case FamilyMembers.split_name(display_name) do
        {first, _} -> titleize(first)
        _ -> nil
      end
    end
  end

  defp last_from_display(display_name, email) do
    if name_like_display?(display_name, email) and
         not flattened_email_local?(display_name, email) do
      case FamilyMembers.split_name(display_name) do
        {_, "-"} -> nil
        {_, last} -> titleize(last)
        _ -> nil
      end
    end
  end

  defp last_from_camel_display(display_name, email) do
    if name_like_display?(display_name, email) and camel_case?(display_name) do
      case split_camel_case(display_name) do
        {_first, last} when last != "-" -> titleize(last)
        _ -> nil
      end
    end
  end

  defp camel_case?(name) when is_binary(name) do
    Regex.match?(~r/[A-Z]/, name) and Regex.match?(~r/[a-z]/, name)
  end

  defp camel_case?(_), do: false

  defp flattened_email_local?(display_name, email) do
    with local when is_binary(local) <- email_local_part(email),
         display when is_binary(display) <- presence(display_name) do
      flattened =
        local
        |> String.split("+", parts: 2)
        |> List.first()
        |> String.replace(~r/[._-]+/, "")

      String.downcase(display) == String.downcase(flattened)
    else
      _ -> false
    end
  end

  defp name_like_display?(display_name, email) do
    case presence(display_name) do
      nil ->
        false

      name ->
        normalized_name = String.downcase(name)
        normalized_email = email && String.downcase(email)

        normalized_email != normalized_name and not String.contains?(name, "@")
    end
  end

  defp name_from_email_local(email, which) do
    case email_local_segments(email) do
      [_] ->
        nil

      segments ->
        case which do
          :first -> titleize(List.first(segments))
          :last -> titleize(List.last(segments))
        end
    end
  end

  defp last_from_first_name_prefix(email, first_name, user_row, application_row) do
    case presence(user_row["first_name"]) ||
           presence(application_row["first_name"]) do
      nil ->
        nil

      _explicit_first ->
        with local when is_binary(local) <- email_local_part(email),
             first when is_binary(first) <- presence(first_name),
             true <- String.length(local) > String.length(first),
             true <-
               String.downcase(local)
               |> String.starts_with?(String.downcase(first)) do
          local
          |> String.slice(String.length(first)..-1//1)
          |> titleize()
        else
          _ -> nil
        end
    end
  end

  defp last_from_email_domain(email) do
    case email do
      nil ->
        nil

      email ->
        email
        |> String.split("@", parts: 2)
        |> case do
          [_local, domain] ->
            domain
            |> String.split(".", parts: 2)
            |> List.first()
            |> titleize()

          _ ->
            nil
        end
    end
  end

  defp email_local_segments(email) do
    case email_local_part(email) do
      nil ->
        []

      local ->
        local
        |> String.split(~r/[._-]+/, trim: true)
        |> Enum.reject(&(&1 == ""))
    end
  end

  defp email_local_part(nil), do: nil
  defp email_local_part(""), do: nil

  defp email_local_part(email) when is_binary(email) do
    email
    |> String.split("@", parts: 2)
    |> case do
      [local, _domain] ->
        local
        |> String.split("+", parts: 2)
        |> List.first()
        |> String.trim()

      _ ->
        nil
    end
  end

  defp split_camel_case(name) when is_binary(name) do
    parts =
      name
      |> String.trim()
      |> then(&Regex.split(~r/(?=[A-Z])/, &1, trim: true))
      |> Enum.reject(&(&1 == ""))

    case parts do
      [] -> nil
      [only] -> {only, "-"}
      [first | rest] -> {first, Enum.join(rest, "")}
    end
  end

  defp titleize(nil), do: nil
  defp titleize(""), do: nil

  defp titleize(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> String.capitalize(String.downcase(trimmed))
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil

  defp presence(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed in ["", "-"], do: nil, else: trimmed
  end

  defp presence(_), do: nil
end
