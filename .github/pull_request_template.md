## Summary

- What changed?
- Why was this needed?

## Validation

- [ ] Server syntax check: `python -m py_compile kokoro_server.py`
- [ ] Extension loaded in Chrome and basic read flow tested
- [ ] Docs updated (README/SECURITY/CHANGELOG) when relevant

## Security Checklist

- [ ] No secrets or credentials added
- [ ] No machine-specific absolute paths introduced
- [ ] Errors remain sanitized for clients
- [ ] Any auth/config changes are documented
