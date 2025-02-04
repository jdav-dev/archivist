defmodule Archivist.SystemCalls do
  @moduledoc false

  @behaviour Archivist

  require Logger

  @model "llama3.2"
  @num_ctx 8192

  @categories ~w[
    identity
    money
    medical
    insurance
    vehicles
    legal
    education
    manuals
    miscellaneous
  ]a

  @slug_length 25

  @system """
  You are a text classification and metadata extraction assistant.  You will be given text
  extracted from a PDF, and your job is to return the following information in valid JSON format:

    - category (string)
      - Must be exactly one of these: #{Enum.join(@categories, ", ")}.
      - This refers to the overall subject area or domain of the document.
      - Below are the category explanations for reference:

        - identity
          - Personal identification and official records.
          - Examples: Passport, driver's license, social security card, birth certificate, visas,
            citizenship papers.

        - money
          - Banking, taxes, financial records, digital receipts, and home-related financial
            matters.
          - Examples: Bank statements, credit card statements, IRS tax returns, W-2s, investment
            records, mortgage documents, lease agreements, property tax records, home-related
            bills (utilities, internet, etc.), software receipts.

        - medical
          - Health records, insurance claims, and medical history.
          - Examples: Doctor visit summaries, prescriptions, lab results, vaccination records,
            dental & vision records.

        - insurance
          - All types of insurance policies and claims.
          - Examples: Health insurance, auto insurance, home insurance, life insurance, policy
            renewal notices.

        - vehicles
          - Documents related to vehicle ownership, maintenance, and insurance.
          - Examples: Car title, registration, loan documents, repair receipts, maintenance logs,
            DMV paperwork.

        - legal
          - Legal documents, employment contracts, estate planning, and home-related legal
            records.
          - Examples: Wills, trusts, power of attorney, court records, notarized documents,
            employment contracts, business ownership documents, home repair contracts, renovation
            permits, legal agreements related to property.

        - education
          - Academic records, certifications, and professional development.
          - Examples: Diplomas, transcripts, student loans, course certificates, professional
            training records.

        - manuals
          - Instruction manuals, warranties, and documentation for products you own.
          - Examples: Appliance manuals, electronics guides, furniture assembly instructions,
            vehicle owner's manuals.

        - miscellaneous
          - A catch-all for documents that don't fit any other category.
          - Examples: Unsorted files, temporary documents, one-off records.

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
  {"category": "money", "date": "2025-01-30", "source": "abc-corp", "title": "invoice-for-jan"}
  ```
  """

  @format %{
    type: :object,
    properties: %{
      category: %{type: :string, enum: @categories},
      date: %{type: :string, format: :date},
      source: %{type: :string},
      title: %{type: :string}
    },
    required: [:category, :date, :source, :title]
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
            "category" => category,
            "date" => date,
            "source" => source,
            "title" => title
          }} <- JSON.decode(response) do
      {:ok,
       %{
         category: category,
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
      {_output, _non_zero_exit_status} -> :error
    end
  end

  @impl Archivist
  def pdf_to_text(path) do
    Logger.info(["Calling pdftotext on ", Path.basename(path)])

    case System.cmd("pdftotext", ["-eol", "unix", path, "-"]) do
      {pdf_text, 0} -> {:ok, pdf_text}
      {_output, _exit_status} -> :error
    end
  end
end
