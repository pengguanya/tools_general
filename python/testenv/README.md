# Python Environment Test Suite

## Why This Exists

This repository serves as a **reference test environment** to verify that IDE/editor Python environment managers correctly detect and load virtual environments.

When working on projects in different directories, you want to ensure your IDE's Python plugin can:
- Detect this specific virtual environment
- Load the correct Python interpreter
- Access packages installed in this environment
- Provide proper code completion and type checking

## What's Inside

- **Test Dependency**: `pyfiglet` (≥1.0.4)
- **Virtual Environment**: `.venv/` (pre-configured)
- **Test Script**: `testenv.py` - Simple import test
- **Package Manager**: `uv` (modern Python package management)

## How to Use

### Initial Setup (One-Time)

If the environment isn't already set up:

```bash
# Install dependencies (creates/syncs .venv)
uv sync

# Or if using traditional tools
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install pyfiglet
```

### Testing Your IDE/Editor

1. **Open your actual project** (in a different directory)
2. **Configure the IDE's Python environment manager** to use this environment:
   - Path: `<basepath>/tools/general/python/testenv/.venv`
   - Or use this directory as a reference environment
3. **Create a test file** in your project or copy and open `testenv.py`
4. **Import and use pyfiglet**:
   ```python
   import pyfiglet
   print(pyfiglet.figlet_format("It Works!"))
   ```
5. **Verify**:
   - No import errors (red squiggles)
   - Autocomplete works for `pyfiglet`
   - Script runs successfully
   - Correct Python version shown (3.11)

Expected output:
```
 ___  _     __        __            _        _
|_ _|| |_   \ \      / /___   _ __ | | ___  | |
 | | | __|   \ \ /\ / // _ \ | '__|| |/ __| | |
 | | | |_     \ V  V /| (_) || |   |   <    |_|
|___| \__|     \_/\_/  \___/ |_|   |_|\_\   (_)
```

## Common IDEs to Test

### Neovim
- **Plugins**: `mason.nvim`, `nvim-lspconfig`, `python-lsp-server`
- **Config**: Set `python.pythonPath` or use `.venv` discovery

### VS Code
- **Extension**: Python (ms-python.python)
- **Command**: `Python: Select Interpreter`

### PyCharm
- **Settings**: Project Interpreter → Add → Existing Environment

### Vim/Vim-Plug
- **Plugins**: `vim-python-pep8-indent`, `jedi-vim`
- **Config**: Let environment variables point to this `.venv`

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Import not found | Check if IDE is using correct interpreter path |
| Wrong Python version | Verify `.python-version` is respected |
| No autocomplete | Restart LSP server or reload IDE |
| Module works in terminal but not IDE | Check IDE's Python path settings |

## Project Structure

```
testenv/
├── .venv/              # Virtual environment (contains pyfiglet)
├── pyproject.toml      # Project metadata & dependencies
├── uv.lock            # Locked dependency versions
├── testenv.py         # Test script
└── README.md          # This file
```

## Notes

- This environment should remain **stable** - avoid upgrading dependencies unnecessarily
- The test package (`pyfiglet`) is intentionally simple and visual
- This directory should not contain actual project code
- Keep this as a clean reference environment
