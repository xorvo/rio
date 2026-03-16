defmodule RioWeb.Helpers.Markdown do
  @moduledoc """
  Markdown rendering helper using Earmark.
  Converts markdown text to sanitized HTML for safe display.
  """

  @doc """
  Converts markdown content to HTML.
  Returns Phoenix.HTML.safe tuple for use in templates.
  Sanitizes output using HtmlSanitizeEx to prevent XSS attacks.
  """
  def render(nil), do: ""
  def render(""), do: ""

  def render(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown, %Earmark.Options{
           code_class_prefix: "language-",
           smartypants: true,
           pure_links: true
         }) do
      {:ok, html, _warnings} ->
        html
        |> HtmlSanitizeEx.markdown_html()
        |> Phoenix.HTML.raw()

      {:error, _html, _errors} ->
        Phoenix.HTML.raw("<p>Error rendering markdown</p>")
    end
  end
end
