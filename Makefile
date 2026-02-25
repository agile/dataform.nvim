DEPS_PATH = tests/.deps

test: deps
	nvim --headless --clean -u tests/init.lua -c "lua MiniTest.run()" -c "qa!"

test_file: deps
	nvim --headless --clean -u tests/init.lua -c "lua MiniTest.run_file('$(FILE)')" -c "qa!"

deps: $(DEPS_PATH)/mini.nvim $(DEPS_PATH)/plenary.nvim

$(DEPS_PATH)/mini.nvim:
	@mkdir -p $(DEPS_PATH)
	git clone --filter=blob:none https://github.com/echasnovski/mini.nvim $@

$(DEPS_PATH)/plenary.nvim:
	@mkdir -p $(DEPS_PATH)
	git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim $@

.PHONY: test test_file deps
