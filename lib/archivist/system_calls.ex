defmodule Archivist.SystemCalls do
  @moduledoc false

  @behaviour Archivist

  require Logger

  @model "llama3.2"
  @num_ctx 8192

  @categories [
    "Vital Records and Identification",
    "Financial Documents",
    "Tax Records",
    "Insurance Documents",
    "Medical and Health Records",
    "Property and Real Estate",
    "Housing and Household",
    "Vehicle and Transportation",
    "Employment and Career",
    "Legal and Estate Planning",
    "Education and Professional Development",
    "Family and Household Members",
    "Warranties and Manuals",
    "Memberships and Subscriptions",
    "Travel and Leisure",
    "Digital Assets and Online Accounts",
    "Sentimental and Historical",
    "Miscellaneous and Other"
  ]

  @slug_length 25

  @system """
  You are a text classification and metadata extraction assistant.  You will be given text
  extracted from a PDF, and your job is to return the following information in valid JSON format:

    - category (string)
      - Must be exactly one of these: #{@categories |> Enum.map(&~s/"#{&1}"/) |> Enum.join(", ")}.
      - This refers to the overall subject area or domain of the document.
      - Below are the category explanations for reference:
          - Vital Records and Identification
            - Description: Documents that establish or verify an individual's identity and
              significant life events.
            - Examples: Birth certificates, marriage or divorce certificates, death certificates
              (for family members), passports, Social Security cards (or equivalents), citizenship
              or naturalization papers, name change documents.
          - Financial Documents
            - Description: Paperwork related to banking, credit, investments, and recurring
              expenses.
            - Examples: Bank statements, credit card statements, loan agreements (mortgage,
              student, car), investment records (stocks, bonds, mutual funds, cryptocurrency),
              budget worksheets, utility bills, subscription invoices.
          - Tax Records
            - Description: All documents needed for tax filing, verification, and historical
              reference.
            - Examples: Past tax returns, W-2/1099 forms (or international equivalents), receipts
              for deductible expenses (charitable donations, medical, business), property tax
              statements.
          - Insurance Documents
            - Description: Policies and claims information for various types of insurance.
            - Examples: Health insurance policy details, life insurance contracts, auto or
              homeowners policies, coverage schedules, claim forms, renewal notices.
          - Medical and Health Records
            - Description: Personal and family health documentation, including treatments and
              prescriptions.
            - Examples: Immunization records, physician or hospital visit summaries, lab test
              results, prescription information, dental/vision care records, documentation of
              chronic conditions.
          - Property and Real Estate
            - Description: Paperwork detailing real property ownership, transactions, and
              improvements.
            - Examples: Mortgage agreements, deeds and titles, closing documents, lease agreements
              for rental properties, receipts for major renovations, HOA (Homeowners Association)
              guidelines.
          - Housing and Household
            - Description: Day-to-day living documents and service agreements for your home.
            - Examples: Rental lease agreements (if renting), utility contracts and bills
              (electricity, water, internet), service or maintenance contracts (e.g., lawn care,
              pest control), appliance manuals, home repair receipts.
          - Vehicle and Transportation
            - Description: Records associated with car ownership, maintenance, and usage.
            - Examples: Vehicle titles, registration papers, auto insurance policies, maintenance
              and service records, warranty details, driver's license copies, parking permits.
          - Employment and Career
            - Description: Information related to current and past employment, as well as
              professional growth.
            - Examples: Employment contracts, offer letters, pay stubs, performance evaluations,
              benefits guides, separation or termination documents, professional certifications,
              résumés/CVs.
          - Legal and Estate Planning
            - Description: Legally binding papers covering estates, end-of-life directives, and
                other legal matters.
            - Examples: Wills, trusts, power of attorney documents, living wills or advance
                directives, guardianship papers, and court or legal settlement documents.
          - Education and Professional Development
            - Description: Records of academic achievements, certifications, and ongoing
              education.
            - Examples: Transcripts, diplomas, course certificates, scholarships or grant info,
              professional licenses, continuing education credits, conference attendance records.
          - Family and Household Members
            - Description: Personal documents specific to each household member or dependent.
            - Examples: Spouse or partner's documents (if kept separately), children's birth
              certificates, school records, immunization details, childcare arrangements, pet
              adoption or vaccination papers.
          - Warranties and Manuals
            - Description: Documentation for product guarantees and user guides.
            - Examples: Warranty information for electronics or appliances, user manuals, extended
              service contracts, purchase receipts for large items or equipment.
          - Memberships and Subscriptions
            - Description: Details on recurring membership-based services or organizations.
            - Examples: Gym memberships, club or association memberships, magazine or streaming
              subscriptions, loyalty or frequent flyer program statements, renewal notices.
          - Travel and Leisure
            - Description: Arrangements and records related to vacations, trips, and leisure
              activities.
            - Examples: Travel itineraries, flight tickets, hotel confirmations, visa
              documentation, travel insurance policies, timeshare contracts, past trip expense
              receipts.
          - Digital Assets and Online Accounts
            - Description: Information and credentials for online identities, cloud services, and
              digital platforms.
            - Examples: Password manager references (stored securely), domain registrations, cloud
              storage subscriptions, digital payment account details (PayPal, etc.), important
              email or social media account notes.
          - Sentimental and Historical
            - Description: Keepsakes and personal or family history items with emotional or
              genealogical importance.
            - Examples: Family photos, letters, journals, genealogy research, copies of heirlooms,
              scrapbooks, memorabilia.
          - Miscellaneous and Other
            - Description: A catch-all for documents that do not neatly fit into other categories.
            - Examples: Personal or hobby-related projects, unusual one-off contracts, event
              memorabilia, or temporary items awaiting proper classification.

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
