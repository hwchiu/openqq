import unittest

from app import Run, emit, validate_fqdn, workspace_path
from fastapi import HTTPException


class DemoValidationTests(unittest.TestCase):
    def test_fqdn_accepts_hostname_and_normalizes_case(self):
        self.assertEqual(validate_fqdn("Example.COM"), "example.com")

    def test_fqdn_rejects_url_and_ip(self):
        for value in ("https://example.com", "127.0.0.1", "10.0.0.0/8"):
            with self.assertRaises(HTTPException):
                validate_fqdn(value)

    def test_workspace_path_strips_directories_but_rejects_hidden_files(self):
        self.assertEqual(workspace_path("nested/input.txt"), "/workspace/input.txt")
        with self.assertRaises(HTTPException):
            workspace_path(".env")


class DemoAsyncTests(unittest.IsolatedAsyncioTestCase):
    async def test_emit_enqueues_one_event(self):
        run = Run(id="test", code=b"print(1)", files=[])
        event = {"type": "stdout", "data": "ok"}
        await emit(run, event)
        self.assertEqual(await run.events.get(), event)
        self.assertTrue(run.events.empty())
