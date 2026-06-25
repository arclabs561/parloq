# Examples

Sample files for the recorder dictation features. See
[`recorder/README.md`](../recorder/README.md) for full usage.

## `dictation.vocab.txt`

A starter vocab file for `recorder dictate`. It fixes recurring mistranscriptions
of proper nouns and identifiers deterministically (no LLM), one `wrong = right`
per line, applied after transcribe and before the text reaches your clipboard.

```sh
# use it automatically (the default path the daemon reads if present)
cp examples/dictation.vocab.txt ~/recordings/.vocab.txt

# or point at it explicitly
recorder dictate --vocab examples/dictation.vocab.txt
recorder dictate install-agent --vocab ~/recordings/.vocab.txt   # at login
```

The entries shipped here are illustrative; replace them with the terms your own
recognizer mishears. Matching is whole-word and case-insensitive, and a
sentence-initial capital is preserved.
