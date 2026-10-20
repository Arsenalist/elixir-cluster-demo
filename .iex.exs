# Show the region in the IEx prompt, so you always know which node you're on:
#
#     tor1> Node.list()
#
# Loaded by `bin/ticketing remote` (the release runs from /app, where the
# Dockerfile copies this file).
region = System.get_env("REGION", "iex")

IEx.configure(
  default_prompt: "#{region}>",
  alive_prompt: "#{region}>"
)
