# Contentful seed

`seed.json` is a complete, re-runnable definition of the catalog space: the five
content types plus 25 entries. It exists so the space can be reset to a known
state — most importantly on Day 4, where the Magento migration wants to be run,
inspected, corrected and run again.

## Contents

| Type | Count | Notes |
|:--|--:|:--|
| `category` | 4 | `dogs`, `cats`, `rabbits`, `exotics`; `rabbits` has `exotics` as parent |
| `segment` | 3 | `vip`, `newsletter`, `firstTimeBuyer` |
| `product` | 12 | see distribution below |
| `ctaVariant` | 4 | two per CTA |
| `cta` | 2 | `free-shipping`, `vip-early-access` |

## Why the products look the way they do

The catalog is a rules-engine test fixture, not a shop. The spread is
deliberate — a uniform catalog makes rules impossible to test, because every
product takes the same branch.

- **6 products under $100, 6 at or above** — so `CartValue gte 100.usd` has
  cases either side.
- **5 available in `EU`, 7 not** — so `not Region("EU")` actually discriminates.
- **4 tagged `vip`**, spanning $129 to $499, so `vip` is not merely a proxy for
  "expensive".
- **3 products in each of the 4 categories.**
- **One GBP and one EUR product.** These force the multi-currency question:
  what should `CartValue gte 100.usd` do when the cart is not in USD? The
  cheapest defensible answer is that a currency mismatch simply does not match —
  no conversion, no exception.

Note that `variantKey` is `control` on two different variants. That is
intentional, and why `variantKey` must not carry a `unique` validation.

## Re-seeding

Authentication comes from `.contentfulrc.json` in the repo root (gitignored),
containing `{"managementToken": "CFPAT-..."}`, or from `--management-token`.
The token itself lives in `.env`.

```sh
npx contentful-cli space import \
  --space-id njbg4vvp7u9g \
  --environment-id master \
  --content-file contentful/seed.json
```

Entry IDs are stable, so re-running **updates** rather than duplicating.
Pre-existing entries keep the random IDs Contentful assigned them; entries
created by this seed use readable IDs (`product-cat-tree-dlx`).

### The import does not publish

`contentful space import` creates and updates entries but leaves them as
drafts, despite `--skip-content-publishing` defaulting to false. Published
entries reported `0` on the run that created these. Entries must then be
published explicitly:

```sh
curl -X PUT \
  -H "Authorization: Bearer $CONTENTFUL_CMA_TOKEN" \
  -H "X-Contentful-Version: <sys.version>" \
  "https://api.contentful.com/spaces/njbg4vvp7u9g/environments/master/entries/<id>/published"
```

Publish referenced entries first — `ctaVariant` before `cta`, since
`cta.variants` carries `size {min: 1}`.

This matters more than it sounds: an unpublished entry is invisible to the
delivery API but visible to preview and management. Skipping the publish step
leaves the CDA serving stale content while every check through the CMA looks
correct.

## Two API asymmetries worth remembering

Both were found the hard way and both affect Day 3 and Day 4 code.

**Field shape.** The delivery and preview APIs return fields flattened to a
single locale (`fields.sku`). The management API returns the locale map
(`fields.sku["en-US"]`). The read client and the migration writer therefore see
different JSON for the same content — a good reason not to share DTOs between
them.

**Validation visibility.** The delivery/preview `content_types` endpoint does
not report `unique`, `size`, `range`, or scalar `in` validations. It reports
`linkContentType` and array *item* validations. Read the model from the
management API; reading it from the delivery API gives a partial picture that
looks complete.
