test:
	nvim --headless --clean -u tests/init.lua -c "lua MiniTest.run()" -c "qa!"

test_file:
	nvim --headless --clean -u tests/init.lua -c "lua MiniTest.run_file('$(FILE)')" -c "qa!"
