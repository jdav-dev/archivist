defmodule Archivist do
  @moduledoc """
  Documentation for `Archivist`.
  """

  alias Archivist.RequestLogger

  require Logger

  @doc """
  Hello world.

  ## Examples

      iex> Archivist.hello()
      :world

  """
  def hello do
    :world
  end

  def extract_pdf_information(path, timeout_seconds \\ 60) do
    client = Ollama.init(receive_timeout: to_timeout(second: timeout_seconds))

    with {:ok, pdf_text} <- pdf_to_text(path),
         messages <- [
           %{
             role: "system",
             content: "You are a document interpreter. Users send you document content as text."
           },
           %{role: "user", content: pdf_text}
         ],
         {:ok, %{"message" => %{"content" => content}}} <-
           Ollama.chat(client,
             #  model: "llama2",
             model: "llama3.2",
             messages: messages,
             format: %{
               type: :object,
               properties: %{
                 document_category: %{
                   type: :string,
                   enum: [
                     "identity",
                     "money",
                     "medical",
                     "insurance",
                     "vehicles",
                     "legal",
                     "education",
                     "manuals",
                     "miscellaneous"
                   ]
                 },
                 document_date: %{type: :string, format: :date},
                 document_short_title: %{type: :string},
                 document_source_entity_name: %{type: :string}
               },
               required: [
                 :document_date,
                 :document_short_title,
                 :document_source_entity_name
               ]
             }
           ) do
      JSON.decode(content)
    end
  end

  def ocr_pdf(path) do
    output_path = Path.join(Path.dirname(path), "ocr_#{Path.basename(path)}")

    case System.cmd("ocrmypdf", [
           "--output-type",
           "pdfa",
           "--quiet",
           "--rotate-pages",
           "--deskew",
           "--skip-text",
           path,
           output_path
         ]) do
      {_output, 0} -> {:ok, output_path}
      {_output, _non_zero_exit_status} -> :error
    end
  end

  def pdf_to_text(path) do
    case System.cmd("pdftotext", ["-eol", "unix", "-q", path, "-"]) do
      {pdf_text, 0} -> {:ok, pdf_text}
      {_output, _exit_status} -> :error
    end
  end
end
