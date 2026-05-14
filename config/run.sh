#docker run --env-file=env -v ./agents_llm_config.json:/testzeus-hercules/agents_llm_config.json -v ./opt:/testzeus-hercules/opt --rm -it hercules:0.2.2
docker run --env-file=env -v ./agents_llm_config.json:/testzeus-hercules/agents_llm_config.json -v ./opt:/testzeus-hercules/opt -v ./data:/tmp/data --name hercules --entrypoint /bin/bash -it hercules:0.2.2-1
