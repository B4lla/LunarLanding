"""Portable CLI defaults and validation; no simulator or training is launched."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("training_cli", ROOT / "python/user_algorithms/train.py")
training = importlib.util.module_from_spec(spec)
spec.loader.exec_module(training)


class TrainingCliTests(unittest.TestCase):
    def test_explicit_executable_overrides_environment_and_path(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "godot.exe"
            executable.touch()
            with patch.dict(os.environ, {"GODOT_EXE": "missing.exe"}):
                args = training.parse_args([
                    "--godot", str(executable), "--steps", "7", "--visual",
                    "--seed", "17", "--port", "55427", "--output", "candidate.zip",
                ])
            self.assertEqual(args.godot, executable.resolve())
            self.assertEqual(args.steps, 7)
            self.assertTrue(args.visual)
            self.assertEqual(args.seed, 17)
            self.assertEqual(args.port, 55427)
            self.assertEqual(args.output, Path("candidate.zip"))

    def test_environment_default_and_training_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "godot.exe"
            executable.touch()
            with patch.dict(os.environ, {"GODOT_EXE": str(executable)}):
                args = training.parse_args([])
            self.assertEqual(args.godot, executable.resolve())
            self.assertEqual(args.steps, 100_000)
            self.assertFalse(args.visual)
            self.assertEqual(args.seed, 42)
            self.assertEqual(args.port, 55423)

    def test_path_is_used_when_environment_is_unset(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(training.shutil, "which", side_effect=[None, "godot4.exe"]):
            self.assertEqual(training.default_godot(), "godot4.exe")

    def test_missing_executable_and_invalid_steps_fail_before_training(self):
        for argv in ([], ["--steps", "0"], ["--steps", "-1"], ["--steps", "abc"]):
            with self.subTest(argv=argv), patch.dict(os.environ, {}, clear=True), patch.object(training.shutil, "which", return_value=None), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as caught:
                    training.parse_args(argv)
                self.assertEqual(caught.exception.code, 2)

    def test_out_of_range_seed_and_port_fail_before_training(self):
        for argv in (["--seed", "-1"], ["--seed", "2147483648"],
                     ["--port", "1023"], ["--port", "65536"]):
            with self.subTest(argv=argv), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as caught:
                    training.parse_args(argv)
                self.assertEqual(caught.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
