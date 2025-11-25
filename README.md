# dfs-complaints

## DeepL translation setup

The admin-side automatic FAQ translations require a valid **DeepL API** authentication key (from a DeepL API subscription). Keys that are issued for CAT-Tool plugins are not accepted by the DeepL API endpoints we call, so plugin keys like `a39d******6ad4` will **not** work here.

* API key: set the DeepL **API** key in the backend environment as `DEEPL_API_KEY` (aliases: `DEEPL_AUTH_KEY`, `DEEPL_KEY`). The server picks it up from the deployed environment (for Vercel, add it under “Environment Variables”).
* API URL: optional override for self-hosted/proxy endpoints via `DEEPL_API_URL` (alias: `DEEPL_ENDPOINT`); default is `https://api-free.deepl.com/v2/translate`.

Only the API subscription keys are supported; CAT-Tool plugin authentication keys cannot authenticate against the DeepL API endpoint.