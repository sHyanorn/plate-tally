public enum Prompt {
    /// The text of eval/prompts/p2.txt, the prompt the evaluation measured (D009). A test compares
    /// the two, so an edit here or there fails until both agree.
    public static let p2 = """
        This is an overhead photo of one plate of food from a cafeteria.
        List every visible food on the plate, at most 20 items. For each item, estimate its weight in grams and its food energy in kilocalories (kcal).
        Reply with only one JSON object in exactly this shape, and nothing else:
        {"items": [{"name": "<food name>", "grams": <number>, "kcal": <number>}]}
        Use an empty list if no food is visible.
        """
}
