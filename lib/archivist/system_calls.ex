defmodule Archivist.SystemCalls do
  @moduledoc false

  @behaviour Archivist

  require Logger

  @model "llama3.2"
  @num_ctx 8192

  @slug_length 25

  @system """
  You are a text classification and metadata extraction assistant.  You will be given text
  extracted from a PDF, and your job is to return the following information in valid JSON format:

    - date (string)
      - Must be a valid ISO 8601 date in the format YYYY-MM-DD.
      - If the text contains multiple dates, choose the one most relevant to the document (e.g.,
        the issuance date, signature date, or an explicitly stated “Date”).
      - If no valid date is found, leave it as "".

    - title (string)
      - Must be a lowercase, hyphen-separated slug of #{@slug_length} characters or less (for
        example, "summer-contract-2025").
      - This field is required and cannot be empty.  If no explicit title is found, create a short
        descriptive slug yourself based on the document's content.

    - source (string)
      - Must be a lowercase, hyphen-separated slug of #{@slug_length} characters or less.
      - This is the name of the company or entity that produced or authored the document.
      - If no source is found, leave it as "".

  If any field is unknown or cannot be determined from the text, use an empty string "".  Do not
  include any additional keys in your JSON response.

  Your output must follow exactly this JSON structure (example with placeholder values):

  ```
  {"date": "2025-01-30", "source": "abc-corp", "title": "invoice-for-jan"}
  ```
  """

  @format %{
    type: :object,
    properties: %{
      date: %{type: :string, format: :date},
      source: %{type: :string},
      title: %{type: :string}
    },
    required: [:date, :source, :title]
  }

  @impl Archivist
  def init do
    client = ollama_client()
    Logger.info("Pulling Ollama model #{inspect(@model)}")

    case Ollama.pull_model(client, name: @model) do
      {:ok, _response} ->
        Logger.info("Pulled Ollama model #{inspect(@model)}")
        :ok

      error ->
        Logger.error("Failed to pull Ollama model #{inspect(@model)}: #{inspect(error)}")
        :error
    end
  end

  defp ollama_client do
    ollama_opts = Application.fetch_env!(:archivist, :ollama)
    Ollama.init(ollama_opts)
  end

  @impl Archivist
  def extract_pdf_information(path) do
    client = ollama_client()

    with {:ok, pdf_text} <- pdf_to_text(path),
         Logger.info(["Sending text from ", Path.basename(path), " to ", @model]),
         {:ok, %{"response" => response}} <-
           Ollama.completion(client,
             model: @model,
             prompt: """
             Below is the text extracted from the PDF. Please analyze it and return your
             structured JSON following the rules above.

             ```
             #{pdf_text}
             ```
             """,
             system: @system,
             format: @format,
             options: %{num_ctx: @num_ctx}
           ),
         {:ok,
          %{
            "date" => date,
            "source" => source,
            "title" => title
          }} <- JSON.decode(response) do
      {:ok,
       %{
         date: date,
         source: Slug.slugify(source, truncate: @slug_length),
         title: Slug.slugify(title, truncate: @slug_length)
       }}
    else
      other ->
        Logger.warning(["Unexpected result while extracting PDF information: ", inspect(other)])
        :error
    end
  end

  @impl Archivist
  def ocr_pdf(path) do
    Logger.info(["Calling ocrmypdf on ", Path.basename(path)])

    case System.cmd("ocrmypdf", [
           "--output-type",
           "pdfa",
           "--rotate-pages",
           "--deskew",
           "--skip-text",
           path,
           path
         ]) do
      {_output, 0} -> :ok
      {output, exit_status} -> {:error, {exit_status, output}}
    end
  end

  @impl Archivist
  def pdf_to_text(path) do
    Logger.info(["Calling pdftotext on ", Path.basename(path)])

    case System.cmd("pdftotext", ["-eol", "unix", path, "-"]) do
      {pdf_text, 0} -> {:ok, pdf_text}
      {output, exit_status} -> {:error, {exit_status, output}}
    end
  end
end
