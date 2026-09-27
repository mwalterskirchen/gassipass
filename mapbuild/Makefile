# The swisstopo releases that the map build reads. See README.md.
TLM_RELEASE := 2026-02
BOUNDARIES_RELEASE := 2026-01

STAC := https://data.geo.admin.ch
TLM_ZIP := data/swisstlm3d_$(TLM_RELEASE)_2056_5728.gpkg.zip
BOUNDARIES_ZIP := data/swissboundaries3d_$(BOUNDARIES_RELEASE)_2056_5728.gpkg.zip
TLM := data/SWISSTLM3D_2026_LV95_LN02.gpkg
BOUNDARIES := data/swissBOUNDARIES3D_1_5_LV95_LN02.gpkg

DIETIKON_PACKAGE := ../doggo/MapPackages/dietikon.sqlite
TEST_PACKAGE := ../doggoTests/Fixtures/dietikon-fixture.sqlite

.PHONY: dietikon test fixture test-package

dietikon: $(TLM) $(BOUNDARIES)
	uv run mapbuild --tlm $(TLM) --boundaries $(BOUNDARIES) \
		--area 243 --map-release $(TLM_RELEASE) --out $(DIETIKON_PACKAGE)

test:
	uv run pytest

fixture: $(TLM) $(BOUNDARIES)
	uv run python scripts/cut_fixture.py --tlm $(TLM) --boundaries $(BOUNDARIES)

test-package:
	uv run mapbuild --tlm tests/fixtures/swisstlm3d.gpkg \
		--boundaries tests/fixtures/swissboundaries3d.gpkg \
		--area 243 --map-release $(TLM_RELEASE) --out $(TEST_PACKAGE)

$(TLM): $(TLM_ZIP)
	unzip -o -d data $(TLM_ZIP) $(notdir $(TLM))
	touch $@

$(BOUNDARIES): $(BOUNDARIES_ZIP)
	unzip -o -d data $(BOUNDARIES_ZIP) $(notdir $(BOUNDARIES))
	touch $@

$(TLM_ZIP):
	mkdir -p data
	curl -fL -o $@ $(STAC)/ch.swisstopo.swisstlm3d/swisstlm3d_$(TLM_RELEASE)/$(notdir $@)

$(BOUNDARIES_ZIP):
	mkdir -p data
	curl -fL -o $@ $(STAC)/ch.swisstopo.swissboundaries3d/swissboundaries3d_$(BOUNDARIES_RELEASE)/$(notdir $@)
