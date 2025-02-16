defmodule Archivist do
  @moduledoc """
  Documentation for `Archivist`.
  """

  @callback extract_pdf_information(path :: Path.t()) ::
              {:ok, %{date: String.t(), source: String.t(), title: String.t()}} | :error

  @callback init :: :ok | :error

  @callback ocr_pdf(path :: Path.t()) :: :ok | {:error, reason :: term()}

  @callback pdf_to_text(path :: Path.t()) ::
              {:ok, pdf_text :: String.t()} | {:error, reason :: term()}

  @implementation Application.compile_env(:archivist, :implementation, Archivist.SystemCalls)

  @doc """
  Extract information needed for archiving a PDF.

  ## Examples

      iex> Archivist.extract_pdf_information(pdf_path)
      {:ok, %{
          date: "2025-01-30",
          source: "abc-corp",
          title: "invoice-for-jan"
        }}

  """
  defdelegate extract_pdf_information(path), to: @implementation

  @doc """
  Initialize any resources needed by an implementation.

  ## Examples

      iex> Archivist.init()
      :ok

  """
  defdelegate init, to: @implementation

  @doc """
  Prepare a PDF file for archiving, including OCR.

  ## Examples

      iex> Archivist.ocr_pdf(pdf_path)
      :ok

  """
  defdelegate ocr_pdf(path), to: @implementation

  @doc """
  Extract the text from a PDF file.

    ## Examples

      iex> Archivist.pdf_to_text(pdf_path)
      {:ok, pdf_text}

  """
  defdelegate pdf_to_text(path), to: @implementation
end
