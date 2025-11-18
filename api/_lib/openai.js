// api/_lib/openai.js
// Zentraler Zugriff auf die OpenAI API inkl. Fallbacks.

import OpenAI from 'openai';

let client;

function getClient() {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return null;
  }
  if (!client) {
    client = new OpenAI({ apiKey });
  }
  return client;
}

export const hasOpenAI = () => Boolean(process.env.OPENAI_API_KEY);

export async function runChatCompletion(messages, { temperature = 0.2, maxTokens = 500 } = {}) {
  const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  const cli = getClient();
  if (!cli) {
    throw new Error('OPENAI_API_KEY missing');
  }
  const response = await cli.chat.completions.create({
    model,
    temperature,
    max_tokens: maxTokens,
    messages,
  });
  return response?.choices?.[0]?.message?.content?.trim() || '';
}
