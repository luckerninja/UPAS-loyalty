# Tag System Examples

## Overview

The Tag system allows creating complex achievements/badges based on user behavior patterns. Tags can have nested logical conditions using AND/OR operators. The system uses a universal `createTag` function where conditions are built using helper functions.

## Using the Universal Tag Creation

### Basic Workflow

1. **Build condition** using helper functions from Tag library
2. **Call `createTag`** with the condition
3. **System automatically evaluates** users for tag eligibility

### Example: Coffee Lover Tag

```motoko
// Build the condition using Tag library functions
let coffeeCondition = Tag.receiptCount(
    ["Coffee Shop", "Starbucks", "Local Cafe"],
    10,
    ?(30 * 24 * 60 * 60 * 1_000_000_000) // 30 days
);

// Create the tag via canister call
let result = await loyaltyActor.createTag(
    "coffee_lover",
    "Coffee Lover",
    "Regular coffee drinker with 10+ purchases in 30 days",
    coffeeCondition,
    "{\"icon\": \"☕️\", \"level\": \"bronze\", \"category\": \"lifestyle\"}",
    50 // reward amount
);
```

### Example: Premium Customer Tag (AND condition)

```motoko
// Build complex condition: VIP credential AND high spending
let premiumCondition = Tag.andCondition([
    Tag.credentialRequired("vip_customer", ["Premium Store"]),
    Tag.totalSpent(["Premium Store"], 5000, null)
]);

let result = await loyaltyActor.createTag(
    "premium_customer",
    "Premium Customer", 
    "VIP member who has spent 5000+ tokens",
    premiumCondition,
    "{\"icon\": \"💎\", \"level\": \"gold\", \"category\": \"status\"}",
    500
);
```

### Example: Complex Nested Conditions

```motoko
// (Coffee OR Tea) AND Big Spender
let beverageCondition = Tag.andCondition([
    Tag.orCondition([
        Tag.receiptCount(["Coffee Shop", "Starbucks"], 10, ?(30 * 24 * 60 * 60 * 1_000_000_000)),
        Tag.receiptCount(["Tea House", "Bubble Tea"], 8, ?(30 * 24 * 60 * 60 * 1_000_000_000))
    ]),
    Tag.totalSpent(["Coffee Shop", "Starbucks", "Tea House", "Bubble Tea"], 1000, ?(90 * 24 * 60 * 60 * 1_000_000_000))
]);

let result = await loyaltyActor.createTag(
    "beverage_enthusiast",
    "Beverage Enthusiast",
    "Regular customer of coffee or tea shops with significant spending",
    beverageCondition,
    "{\"icon\": \"☕️🫖\", \"level\": \"silver\", \"category\": \"lifestyle\"}",
    200
);
```

## Real-World Tag Creation Examples

### 1. Fitness Enthusiast
```motoko
let fitnessCondition = Tag.andCondition([
    Tag.receiptCount(["Gym", "Sports Store"], 15, ?(30 * 24 * 60 * 60 * 1_000_000_000)),
    Tag.totalSpent(["Health Food Store"], 500, ?(30 * 24 * 60 * 60 * 1_000_000_000))
]);

await loyaltyActor.createTag(
    "fitness_enthusiast",
    "Fitness Enthusiast",
    "Regular gym goer who also invests in healthy eating",
    fitnessCondition,
    "{\"icon\": \"💪\", \"level\": \"gold\", \"category\": \"health\"}",
    300
);
```

### 2. Tech Enthusiast with Complex Logic
```motoko
// (High Electronics Spending OR Gaming Purchases) AND Early Adopter Credential
let techCondition = Tag.andCondition([
    Tag.orCondition([
        Tag.totalSpent(["Electronics Store"], 5000, null),
        Tag.receiptCount(["Gaming Store"], 10, ?(60 * 24 * 60 * 60 * 1_000_000_000))
    ]),
    Tag.credentialRequired("early_adopter", ["Tech Store"])
]);

await loyaltyActor.createTag(
    "tech_enthusiast",
    "Tech Enthusiast",
    "Technology lover with high spending or gaming purchases plus early adopter status",
    techCondition,
    "{\"icon\": \"🔧\", \"level\": \"platinum\", \"category\": \"technology\"}",
    1000
);
```

### 3. VIP Tier Progression with Tag Dependencies
```motoko
// Bronze VIP: Basic spending
let bronzeCondition = Tag.totalSpent(["Any Store"], 1000, ?(90 * 24 * 60 * 60 * 1_000_000_000));

await loyaltyActor.createTag(
    "bronze_vip",
    "Bronze VIP",
    "Customer with 1000+ tokens spent in 90 days",
    bronzeCondition,
    "{\"icon\": \"🥉\", \"level\": \"bronze\", \"category\": \"status\"}",
    100
);

// Silver VIP: Bronze tag + Frequency
let silverCondition = Tag.andCondition([
    Tag.tagRequired("bronze_vip"),
    Tag.receiptCount(["Any Store"], 50, ?(90 * 24 * 60 * 60 * 1_000_000_000))
]);

await loyaltyActor.createTag(
    "silver_vip", 
    "Silver VIP",
    "Bronze VIP with 50+ purchases in 90 days",
    silverCondition,
    "{\"icon\": \"🥈\", \"level\": \"silver\", \"category\": \"status\"}",
    250
);

// Gold VIP: Silver tag + Premium purchases
let goldCondition = Tag.andCondition([
    Tag.tagRequired("silver_vip"),
    Tag.totalSpent(["Premium Stores"], 5000, ?(180 * 24 * 60 * 60 * 1_000_000_000))
]);

await loyaltyActor.createTag(
    "gold_vip",
    "Gold VIP", 
    "Silver VIP with 5000+ premium spending in 180 days",
    goldCondition,
    "{\"icon\": \"🥇\", \"level\": \"gold\", \"category\": \"status\"}",
    500
);
```

## API Usage Examples

### Creating Tags
```javascript
// From frontend or CLI
const condition = {
  And: [
    {
      Simple: {
        ReceiptCount: {
          storeNames: ["Coffee Shop", "Bakery"],
          minCount: 5,
          timeWindow: [1000000000] // Optional: 30 days in nanoseconds
        }
      }
    },
    {
      Simple: {
        TotalSpent: {
          storeNames: ["Coffee Shop"],
          minAmount: 200,
          timeWindow: []
        }
      }
    }
  ]
};

const result = await loyaltyActor.createTag(
  "coffee_regular",
  "Coffee Regular",
  "Regular customer with 5+ visits and 200+ spending",
  condition,
  JSON.stringify({icon: "☕", level: "bronze"}),
  75
);
```

### Managing Tags
```javascript
// List all tags
const tags = await loyaltyActor.listTagSchemes();

// Get specific tag
const coffeeTag = await loyaltyActor.getTagScheme("coffee_lover");

// Get user's tags
const userTags = await loyaltyActor.getUserTags(userPrincipal);

// Evaluate user for new tags
const newTags = await loyaltyActor.evaluateUserTags(userPrincipal);

// Update tag reward
await loyaltyActor.updateTagReward("coffee_lover", 100);

// Deactivate tag
await loyaltyActor.deactivateTag("old_tag");
```

## Available Condition Types

### Simple Conditions
- **`receiptCount`**: Number of receipts from specific stores
- **`totalSpent`**: Total amount spent at specific stores  
- **`credentialRequired`**: Must have specific credential from specific issuers
- **`tagRequired`**: Must have another tag

### Logical Operators
- **`andCondition`**: All conditions must be true
- **`orCondition`**: At least one condition must be true

### Time Windows
- Use `null` for no time limit
- Use `?(nanoseconds)` for time-limited conditions
- Common values:
  - 1 day: `?(24 * 60 * 60 * 1_000_000_000)`
  - 30 days: `?(30 * 24 * 60 * 60 * 1_000_000_000)`
  - 90 days: `?(90 * 24 * 60 * 60 * 1_000_000_000)`

## Best Practices

1. **Hierarchical Tags**: Use `tagRequired` to create tier progressions
2. **Clear Naming**: Use descriptive IDs like "coffee_lover" not "tag_001"
3. **Balanced Conditions**: Don't make requirements too easy or too hard
4. **Metadata**: Include rich metadata for frontend display
5. **Testing**: Start with simple conditions and gradually add complexity
6. **Performance**: Consider that complex nested conditions take more computation

This universal system allows creating any logical combination of conditions while maintaining clean, readable code and flexible tag management. 