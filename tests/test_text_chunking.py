"""Regression tests for sentence-preserving Kokoro text chunks."""

import ast
from pathlib import Path
import re
import unittest


SERVER_PATH = Path(__file__).resolve().parents[1] / "kokoro_server.py"


def load_iter_text_chunks():
    """Load the production chunker without importing TTS/audio dependencies."""
    tree = ast.parse(SERVER_PATH.read_text(encoding="utf-8"), filename=str(SERVER_PATH))
    function = next(
        node for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "iter_text_chunks"
    )
    module = ast.Module(body=[function], type_ignores=[])
    namespace = {"re": re}
    exec(compile(module, str(SERVER_PATH), "exec"), namespace)
    return namespace["iter_text_chunks"]


class IterTextChunksTests(unittest.TestCase):
    def test_keeps_an_overlong_sentence_intact_before_starting_next_sentence(self):
        iter_text_chunks = load_iter_text_chunks()
        first_sentence = "A" * 301 + "."
        second_sentence = "The next sentence begins here."

        chunks = list(iter_text_chunks(f"{first_sentence} {second_sentence}", max_chars=300))

        self.assertEqual(chunks, [first_sentence, second_sentence])


if __name__ == "__main__":
    unittest.main()
