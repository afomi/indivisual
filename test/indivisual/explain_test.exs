defmodule Indivisual.ExplainTest do
  @moduledoc """
  Explanation is the contextual half of "what does this mean?" — the half a
  glossary cannot answer. These cover the parts that must not drift: the prompt
  stays grounded in the record, the cache keys on content so a changed record
  cannot read a stale explanation, and a missing backend degrades rather than
  raises.
  """
  use ExUnit.Case, async: false

  alias Indivisual.Atlas.Event
  alias Indivisual.Explain
  alias Indivisual.Explain.Cache

  setup do
    Cache.clear()
    :ok
  end

  defp event(attrs \\ %{}) do
    Event.new!(
      Map.merge(
        %{
          "event_id" => "evt:#{System.unique_integer([:positive])}",
          "source_id" => "test-source",
          "stream_id" => "test",
          "sequence" => [1],
          "event_type" => "civic.plan.adopted",
          "observed_at" => ~U[2026-09-10 16:00:00Z],
          "occurred_at" => ~U[2024-04-09 00:00:00Z],
          "object" => ["plan:eltsp"],
          "provenance" => %{"content_hash" => "hash-a"},
          "truth_state" => "observed",
          "payload" => %{"title" => "A plan was adopted"}
        },
        attrs
      )
    )
  end

  describe "prompt_for/3" do
    test "carries the record's own facts" do
      prompt = Explain.prompt_for(event(), [])

      assert prompt =~ "civic.plan.adopted"
      assert prompt =~ "A plan was adopted"
      assert prompt =~ "plan:eltsp"
      assert prompt =~ "April 9, 2024"
    end

    test "spells out the truth state rather than naming it" do
      prompt = Explain.prompt_for(event(%{"truth_state" => "proposed"}), [])

      assert prompt =~ "put forward, not yet approved"
      refute prompt =~ "truth_state: proposed"
    end

    test "instructs against inventing context" do
      prompt = Explain.prompt_for(event(), [])

      assert prompt =~ "Use ONLY the facts"
      assert prompt =~ "Saying less is correct"
    end

    test "uses the publisher's title when one is known" do
      sources = %{"test-source" => %{title: "Parks Commission staff report"}}
      prompt = Explain.prompt_for(event(), [], sources)

      assert prompt =~ "Parks Commission staff report"
      refute prompt =~ "Asserted by: test-source"
    end

    test "falls back to the source id when no title is known" do
      assert Explain.prompt_for(event(), []) =~ "test-source"
    end

    test "includes other records touching the same entities" do
      subject = event()
      related = event(%{"payload" => %{"title" => "An earlier decision"}})
      unrelated = event(%{"object" => ["plan:other"]})

      prompt = Explain.prompt_for(subject, [subject, related, unrelated])

      assert prompt =~ "An earlier decision"
      refute prompt =~ "plan:other"
    end

    test "omits the related block entirely when nothing else matches" do
      refute Explain.prompt_for(event(), []) =~ "Other records touching"
    end
  end

  describe "caching" do
    test "a second call is served from cache" do
      e = event()

      refute Explain.cached?(e)
      {:ok, first} = Explain.explain_event(e, [])
      assert Explain.cached?(e)

      {:ok, second} = Explain.explain_event(e, [])
      assert first == second
    end

    test "a changed record does not read the old explanation" do
      original = event()
      {:ok, _} = Explain.explain_event(original, [])
      assert Explain.cached?(original)

      # Same id, different content: the hash is what makes this detectable.
      edited = %{original | provenance: %{"content_hash" => "hash-b"}}

      refute Explain.cached?(edited),
             "a changed record must not inherit the previous explanation"
    end

    test "different events cache separately" do
      a = event()
      b = event()

      {:ok, _} = Explain.explain_event(a, [])

      assert Explain.cached?(a)
      refute Explain.cached?(b)
    end

    test "cache: false bypasses the cache" do
      e = event()
      {:ok, _} = Explain.explain_event(e, [])

      assert {:ok, _} = Explain.explain_event(e, [], cache: false)
    end
  end

  describe "degrading without a backend" do
    test "returns :unavailable rather than raising when disabled" do
      original = Application.get_env(:indivisual, Explain)

      on_exit(fn -> Application.put_env(:indivisual, Explain, original) end)
      Application.put_env(:indivisual, Explain, Keyword.put(original, :enabled, false))

      refute Explain.available?()
      assert {:error, :unavailable} = Explain.explain_event(event(), [])
    end
  end

  describe "models a reader can choose between" do
    test "come from the adapter" do
      assert Explain.models() == {:ok, ["fake-small", "fake-large"]}
    end

    test "the cache is per model: one's words are not another's" do
      e = event()
      Indivisual.Explain.Cache.clear()

      assert {:ok, small} = Explain.explain_event(e, [e], model: "fake-small")
      assert {:ok, large} = Explain.explain_event(e, [e], model: "fake-large")

      assert small =~ "(fake-small)"
      assert large =~ "(fake-large)"
      assert Explain.cached?(e, "fake-small")
      assert Explain.cached?(e, "fake-large")
      refute Explain.cached?(e, "never-asked")
    end

    test "Ollama's list is filtered to models that can write" do
      embedding? = &Indivisual.Explain.Ollama.embedding?/1

      # The shapes /api/tags really returns on this machine.
      assert embedding?.(%{
               "name" => "nomic-embed-text:latest",
               "details" => %{"family" => "nomic-bert"}
             })

      assert embedding?.(%{"name" => "qwen3-embedding:8b", "details" => %{"family" => "qwen3"}})
      assert embedding?.(%{"name" => "all-minilm", "details" => %{"families" => ["bert"]}})

      refute embedding?.(%{"name" => "qwen3:8b", "details" => %{"family" => "qwen3"}})
      refute embedding?.(%{"name" => "llama3.2:1b", "details" => %{"family" => "llama"}})
      refute embedding?.(%{"name" => "no-details"})
    end
  end
end
