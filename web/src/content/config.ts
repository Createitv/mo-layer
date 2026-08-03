import { defineCollection, z } from 'astro:content';

const articles = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    description: z.string(),
    locale: z.string(),
    pageSlug: z.string(),
    translationKey: z.string(),
    category: z.string(),
    keywords: z.array(z.string()),
    updatedAt: z.string()
  })
});

export const collections = { articles };
