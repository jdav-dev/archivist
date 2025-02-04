defmodule Archivist.WorkerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Mox

  alias Archivist.Worker

  setup do
    stub(Archivist.Mock, :init, fn -> :ok end)
    :ok
  end

  describe "init/1" do
    test "logs the inbox and returns initial state" do
      archive = "/some/archive"
      check_interval = to_timeout(second: 30)
      inbox = "/some/inbox"

      worker_opts = [
        archive: archive,
        check_interval: check_interval,
        inbox: inbox
      ]

      {result, info_log} =
        with_log([level: :info], fn ->
          Worker.init(worker_opts)
        end)

      assert result ==
               {:ok,
                %Worker{
                  archive: archive,
                  check_interval: check_interval,
                  inbox: inbox
                }, {:continue, :next_file}}

      assert info_log =~ "Watching inbox: #{inspect(inbox)}"
    end

    test "raises for missing opts" do
      worker_opts = [
        archive: "/some/archive",
        check_interval: to_timeout(second: 30),
        inbox: "/some/inbox"
      ]

      for key <- Keyword.keys(worker_opts) do
        invalid_opts = Keyword.delete(worker_opts, key)

        assert_raise KeyError, fn ->
          Worker.init(invalid_opts)
        end
      end
    end
  end

  describe "handle_continue/2" do
    setup do
      base_dir = Path.join([System.tmp_dir!(), inspect(__MODULE__), to_string(System.os_time())])
      archive = Path.join(base_dir, "archive")
      inbox = Path.join(base_dir, "inbox")

      on_exit(fn -> File.rm_rf!(base_dir) end)
      File.mkdir_p!(archive)
      File.mkdir_p!(inbox)

      state = %Worker{
        archive: archive,
        check_interval: to_timeout(second: 30),
        inbox: inbox
      }

      {:ok, archive: archive, inbox: inbox, state: state}
    end

    test ":next_file continues if there is a file in the inbox", %{inbox: inbox, state: state} do
      pdf_path = Path.join(inbox, "archive_me.pdf")
      File.touch!(pdf_path)

      assert {:noreply, state, {:continue, {:archive, pdf_path}}} ==
               Worker.handle_continue(:next_file, state)
    end

    test ":next_file returns timeout if there are no files in the inbox", %{state: state} do
      assert {:noreply, state, state.check_interval} == Worker.handle_continue(:next_file, state)
    end

    test ":next_file ignores files without the .pdf extension", %{inbox: inbox, state: state} do
      inbox
      |> Path.join("not_a_pdf.txt")
      |> File.touch!()

      assert {:noreply, state, state.check_interval} == Worker.handle_continue(:next_file, state)
    end

    test ":next_file ignores directories and symlinks", %{
      archive: archive,
      inbox: inbox,
      state: state
    } do
      archived_path = Path.join(archive, "archived.pdf")
      File.touch!(archived_path)

      dir_path = Path.join(inbox, "dir.pdf")
      File.mkdir!(dir_path)

      symlink_path = Path.join(inbox, "symlink.pdf")
      File.ln_s!(archived_path, symlink_path)

      assert {:noreply, state, state.check_interval} == Worker.handle_continue(:next_file, state)
    end

    test ":next_file ignores files in the failed files set", %{inbox: inbox, state: state} do
      failed_path = Path.join(inbox, "failed.pdf")
      File.touch!(failed_path)

      updated_state = struct!(state, failed: MapSet.put(state.failed, failed_path))

      assert {:noreply, updated_state, updated_state.check_interval} ==
               Worker.handle_continue(:next_file, updated_state)
    end

    test ":archive uses the Archivist functions to archive the specified file", %{
      archive: archive,
      inbox: inbox,
      state: state
    } do
      pdf_path = Path.join(inbox, "archive_me.pdf")
      File.touch!(pdf_path)

      pdf_info = %{
        category: "money",
        date: "2025-01-30",
        source: "abc-corp",
        title: "invoice-for-jan"
      }

      Archivist.Mock
      |> expect(:ocr_pdf, fn ^pdf_path -> :ok end)
      |> expect(:extract_pdf_information, fn ^pdf_path -> {:ok, pdf_info} end)

      {result, info_log} =
        with_log([level: :info], fn ->
          Worker.handle_continue({:archive, pdf_path}, state)
        end)

      assert {:noreply, state, {:continue, :next_file}} == result

      archive_path = Path.join([archive, "money", "2025-01-30_abc-corp_invoice-for-jan.pdf"])
      assert File.exists?(archive_path)

      assert info_log =~ "Archiving #{inspect(pdf_path)}"
      assert info_log =~ ~s/Moving "archive_me.pdf" to #{inspect(archive_path)}/
    end

    test ":archive skips files that fail OCR", %{inbox: inbox, state: state} do
      pdf_path = Path.join(inbox, "archive_me.pdf")
      File.touch!(pdf_path)

      expect(Archivist.Mock, :ocr_pdf, fn _pdf_path -> {:error, {1, "some error"}} end)

      {result, error_log} =
        with_log([level: :error], fn ->
          Worker.handle_continue({:archive, pdf_path}, state)
        end)

      assert {:noreply, updated_state, {:continue, :next_file}} = result
      assert MapSet.member?(updated_state.failed, pdf_path)

      assert error_log =~ ~s/Failed to archive "archive_me.pdf": :error/
    end

    test ":archive skips files that fail to extract PDF information", %{
      inbox: inbox,
      state: state
    } do
      pdf_path = Path.join(inbox, "archive_me.pdf")
      File.touch!(pdf_path)

      Archivist.Mock
      |> expect(:ocr_pdf, fn _pdf_path -> :ok end)
      |> expect(:extract_pdf_information, fn _pdf_path -> :error end)

      {result, error_log} =
        with_log([level: :error], fn ->
          Worker.handle_continue({:archive, pdf_path}, state)
        end)

      assert {:noreply, updated_state, {:continue, :next_file}} = result
      assert MapSet.member?(updated_state.failed, pdf_path)

      assert error_log =~ ~s/Failed to archive "archive_me.pdf": :error/
    end

    test ":archive retries files that already exist in the archive", %{
      archive: archive,
      inbox: inbox,
      state: state
    } do
      pdf_path = Path.join(inbox, "archive_me.pdf")
      File.touch!(pdf_path)

      pdf_info = %{
        category: "money",
        date: "2025-01-30",
        source: "abc-corp",
        title: "invoice-for-jan"
      }

      category_path = Path.join(archive, "money")
      File.mkdir_p!(category_path)
      archive_path = Path.join(category_path, "2025-01-30_abc-corp_invoice-for-jan.pdf")
      File.touch!(archive_path)

      Archivist.Mock
      |> expect(:ocr_pdf, fn _pdf_path -> :ok end)
      |> expect(:extract_pdf_information, fn _pdf_path -> {:ok, pdf_info} end)

      {result, info_log} =
        with_log([level: :info], fn ->
          Worker.handle_continue({:archive, pdf_path}, state)
        end)

      assert {:noreply, updated_state, {:continue, :next_file}} = result
      refute MapSet.member?(updated_state.failed, pdf_path)
      assert File.exists?(pdf_path)

      assert info_log =~ ~s/Moving "archive_me.pdf" to #{inspect(archive_path)}/
      assert info_log =~ "Skipping #{inspect(archive_path)} (file exists)"
    end
  end

  describe "handle_info/2" do
    test ":timeout continues to the next file" do
      state = %Worker{
        archive: "/some/archive",
        check_interval: to_timeout(second: 30),
        inbox: "/some/inbox"
      }

      assert {:noreply, state, {:continue, :next_file}} == Worker.handle_info(:timeout, state)
    end
  end
end
