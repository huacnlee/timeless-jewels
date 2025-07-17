#!/usr/bin/env bash
if [ "$#" -ne 1 ]; then
    echo "usage: $0 <tree_version> <game_version>"
    echo ""
    echo "example: $0 3.26"
    exit 1
fi

version=$1

set -ex

curl -L "https://github.com/grindinggear/skilltree-export/raw/refs/heads/master/data.json" | gzip > ./data/SkillTree.json.gz

curl -L "https://go-pob-data.pages.dev/data/$version/raw/AlternatePassiveAdditions.json.gz" > ./data/alternate_passive_additions.json.gz
curl -L "https://go-pob-data.pages.dev/data/$version/raw/AlternatePassiveSkills.json.gz" > ./data/alternate_passive_skills.json.gz
curl -L "https://go-pob-data.pages.dev/data/$version/raw/AlternateTreeVersions.json.gz" > ./data/alternate_tree_versions.json.gz
curl -L "https://go-pob-data.pages.dev/data/$version/raw/PassiveSkills.json.gz" > ./data/passive_skills.json.gz
curl -L "https://go-pob-data.pages.dev/data/$version/raw/Stats.json.gz" > ./data/stats.json.gz

curl -L "https://go-pob-data.pages.dev/data/$version/stat_translations/en/stat_descriptions.json.gz" > ./data/trs/en/stat_descriptions.json.gz
curl -L "https://go-pob-data.pages.dev/data/$version/stat_translations/en/passive_skill_stat_descriptions.json.gz" > ./data/trs/en/passive_skill_stat_descriptions.json.gz
curl -L "https://go-pob-data.pages.dev/data/$version/stat_translations/en/passive_skill_aura_stat_descriptions.json.gz" > ./data/trs/en/passive_skill_aura_stat_descriptions.json.gz

curl -L "https://go-pob-data.pages.dev/data/$version/stat_translations/cn/stat_descriptions.json.gz" > ./data/trs/zh/stat_descriptions.json.gz
curl -L "https://go-pob-data.pages.dev/data/$version/stat_translations/cn/passive_skill_stat_descriptions.json.gz" > ./data/trs/zh/passive_skill_stat_descriptions.json.gz
curl -L "https://go-pob-data.pages.dev/data/$version/stat_translations/cn/passive_skill_aura_stat_descriptions.json.gz" > ./data/trs/zh/passive_skill_aura_stat_descriptions.json.gz

go generate -tags tools -x ./...
