defmodule Indivisual.Atlas.MAP do
  @moduledoc """
  An Atlas event as the data of a Bitcoin transaction: the **same shape, not a
  translation of it**.

  This writes nothing to any chain. It is the pure function that says what an
  event WOULD be as transaction data, so the envelope can be kept congruent with
  it now, while changing a field name is still free.

  ## The carrier: MAP in an `OP_RETURN`

  Two neighbouring projects were read for their opinions and agree. `qart` writes
  every event as `OP_FALSE OP_RETURN <MAP prefix> "SET" <key> <value> …`, and the
  Yours Wallet provider types MAP as `{app: string, type: string, [key]: string}`
  — the same two required keys — and takes transaction data as `data: string[]`,
  one hex string per push. So the list this module returns, hex-encoded, IS the
  argument to a wallet's `sendBsv`: "write this event to chain" is a hand-off,
  with nothing in between to get wrong.

  ## The rules (qart's `docs/PROTOCOL.md`, kept verbatim)

    * values are UTF-8 strings; integers are decimal strings; a list is
      comma-separated
    * an absent field is OMITTED, never written as an empty string
    * `app` and `type` lead, and `type` carries a version: `log_v1`
    * every other key follows in sorted order, so the same event is always the
      same bytes — the property a content hash, and later an anchor, depend on

  ## What maps to what

  | Event | MAP key | Note |
  |---|---|---|
  | — | `app` | `"indivisual"` |
  | `event_type` | `type`, `verb` | `type` is the schema (`log_v1`); the verb is data |
  | `actor` | `actor` | a ref today; an identity PUBKEY once people sign in |
  | `object` | `object` | comma-separated refs |
  | `occurred_at` | `timestamp` | Unix seconds: the actor's CLAIMED time |
  | content hash | `data_hash` | SHA-256 of the canonical event; the title stays off-chain |
  | `event_id` | `id` | |

  The block's own time, the txid and the height are the NETWORK's account of the
  same event. They arrive after confirmation, are never part of the hash, and are
  nil in the normal case: hash first, anchor optionally.

  **Only hashes and refs, never prose.** `title`, `body` and the captured line do
  not appear: what a person wrote stays off-chain (`docs/chain-permanence-vs-privacy.tldr`).
  """

  alias Indivisual.Atlas.Event

  @prefix "1PuQa7K62MiKCtssSLKy1kh56WWU7MtUR5"
  @app "indivisual"
  @version 1

  @doc "The MAP protocol prefix (a Bitcom address)."
  def prefix, do: @prefix

  @doc """
  The event as MAP key-values, in write order: `app`, `type`, then the rest sorted.
  """
  def pairs(%Event{} = event) do
    rest =
      [
        {"actor", event.actor},
        {"data_hash", data_hash(event)},
        {"id", event.event_id},
        {"object", Enum.join(event.object, ",")},
        {"timestamp",
         event |> Event.effective_time() |> DateTime.to_unix() |> Integer.to_string()},
        {"truth", event.truth_state},
        {"verb", verb(event)}
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.sort_by(&elem(&1, 0))

    [{"app", @app}, {"type", "#{schema(event)}_v#{@version}"} | rest]
  end

  @doc """
  The pushdata list: `[prefix, "SET", key, value, …]`. After `OP_FALSE OP_RETURN`
  this is the whole data output.
  """
  def pushes(%Event{} = event),
    do: [@prefix, "SET" | Enum.flat_map(pairs(event), fn {key, value} -> [key, value] end)]

  @doc "The same list as lowercase hex strings: a wallet's `sendBsv` `data` argument."
  def hex(%Event{} = event), do: event |> pushes() |> Enum.map(&Base.encode16(&1, case: :lower))

  @doc "Bytes the data would occupy in a transaction, pushdata opcodes included."
  def byte_size(%Event{} = event) do
    # OP_FALSE OP_RETURN, then each push: a 1-byte length below 76 bytes, else
    # OP_PUSHDATA1 + length.
    2 +
      (event
       |> pushes()
       |> Enum.map(&(Kernel.byte_size(&1) + if(Kernel.byte_size(&1) < 76, do: 1, else: 2)))
       |> Enum.sum())
  end

  # The schema is the event's first segment (`log`, `civic`, `atlas`); the verb is
  # the rest. `log.met` and `log.read` are one schema with two verbs.
  defp schema(%Event{event_type: type}), do: type |> String.split(".", parts: 2) |> hd()

  defp verb(%Event{payload: %{"verb" => verb}}) when is_binary(verb), do: verb

  defp verb(%Event{event_type: type}) do
    case String.split(type, ".", parts: 2) do
      [_, rest] -> rest
      [only] -> only
    end
  end

  defp data_hash(%Event{provenance: %{"content_hash" => hash}}) when is_binary(hash), do: hash

  defp data_hash(%Event{} = event) do
    event
    |> Map.from_struct()
    |> Map.take([:event_id, :event_type, :actor, :object, :occurred_at, :payload])
    |> Event.content_hash()
  end
end
