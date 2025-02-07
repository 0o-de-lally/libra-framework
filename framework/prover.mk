# Prover Tests are WIP
# These are the prover tests that have been written
# and are known to pass
PROVER_TESTS = demo ol_account slow sacred

VENDOR_TESTS = chain_id guid

# Formal verification of each framework using the Move prover
prove:
	@cd move-stdlib && \
	echo "Testing move-stdlib" && \
	find sources -type f -name "*.move" ! -name "*.spec.move" | sed 's/\.move$$//' | \
	xargs -I {} sh -c 'echo "Testing file: {}"; libra move prove -f {} || echo "Error in file: {}"'

	@cd vendor-stdlib && \
	echo "Testing vendor-stdlib" && \
	find sources -type f -name "*.move" ! -name "*.spec.move" | sed 's/\.move$$//' | \
	xargs -I {} sh -c 'echo "Testing file: {}"; libra move prove -f {} || echo "Error in file: {}"'

	@cd libra-framework && \
	for i in ${PROVER_TESTS} ${VENDOR_TESTS}; do \
			libra move prove -f $$i; \
	done
