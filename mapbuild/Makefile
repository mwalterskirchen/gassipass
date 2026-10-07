# The swisstopo releases that the map build reads. See README.md.
TLM_RELEASE := 2026-02
BOUNDARIES_RELEASE := 2026-01

STAC := https://data.geo.admin.ch
TLM_ZIP := data/swisstlm3d_$(TLM_RELEASE)_2056_5728.gpkg.zip
BOUNDARIES_ZIP := data/swissboundaries3d_$(BOUNDARIES_RELEASE)_2056_5728.gpkg.zip
TLM := data/SWISSTLM3D_2026_LV95_LN02.gpkg
BOUNDARIES := data/swissBOUNDARIES3D_1_5_LV95_LN02.gpkg

# The zones where dogs are banned all year. See README.md.
DOG_BAN_ZONES := dog_ban_zones.geojson

# The cantons that the app includes. Each one gets its own map package.
CANTONS := zh ag
PACKAGE_DIR := ../map-packages

# The engine tests read this package. It comes from the test fixture.
FIXTURE := tests/fixtures
TEST_PACKAGE := ../ios/gassipassTests/MapPackages/fixture.sqlite

.PHONY: packages test test-package fixture FORCE

packages: $(CANTONS:%=$(PACKAGE_DIR)/%.sqlite)

# FORCE builds the package again also when only the map build has changed.
$(PACKAGE_DIR)/%.sqlite: $(TLM) $(BOUNDARIES) FORCE
	uv run mapbuild --tlm $(TLM) --boundaries $(BOUNDARIES) \
		--dog-ban-zones $(DOG_BAN_ZONES) --canton $* \
		--map-release $(TLM_RELEASE) --out $@

test:
	uv run pytest

test-package:
	mkdir -p $(dir $(TEST_PACKAGE))
	uv run mapbuild --tlm $(FIXTURE)/swisstlm3d.gpkg --boundaries $(FIXTURE)/swissboundaries3d.gpkg \
		--dog-ban-zones $(FIXTURE)/dog_ban_zones.geojson --area 243 --area 4040 --area 246 \
		--map-release fixture --out $(TEST_PACKAGE)

fixture: $(TLM) $(BOUNDARIES)
	uv run python scripts/cut_fixture.py --tlm $(TLM) --boundaries $(BOUNDARIES)

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
