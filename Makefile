VIM ?= vim

.PHONY: test
test:
	@$(VIM) -Nu NONE -es -S test/run.vim && echo "" || (echo "tests failed"; exit 1)
