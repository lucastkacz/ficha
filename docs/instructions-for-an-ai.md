# Instructions for an AI: a file of cards for Ficha

Ficha is a flashcard app for the Mac: every so often it shows its user a small card, and it spaces each card by how well they know it. It imports cards from a text file, the same file it exports, and these instructions say how to write one. In Ficha, "Copy Instructions for an AI" in the Cards window's Import sheet copies them, to paste into an AI chat along with what you want cards about. You can also follow them to write a file yourself.

## What to do

1. Write cards about what the user asks for, in the language they write in. Each card holds one small thing to remember: its front a word, a name or a question, and its back a sentence or two.
2. Write the file as the next section describes, with every card on it.
3. Answer with the file alone, and nothing before or after it: one code block holding the whole file, or a `.txt` file to download when you can make files, named after its subject, like `Biology.txt`. The user saves it as a UTF-8 text file and imports it in Ficha, which proposes the file's name as a tag for every card.

## The file

The file is UTF-8 plain text, and its cards hold plain text too, with no HTML or Markdown.

It starts with these four lines, exactly as they are, with a tab between the column names:

```text
#separator:tab
#html:false
#columns:Front	Back	Tags	Type	Source
#tags column:3
```

Then each card has a line of its own, with five columns separated by tab characters, in this order:

1. **Front**: what the card shows first, such as a word, a name or a question.
2. **Back**: what the user tries to remember, such as a meaning, an answer, or who said a quote.
3. **Tags**: the subjects the card belongs to, separated by spaces, such as `history philosophy`. An underscore stands for a space inside a tag: `cell_biology` is the tag "cell biology". It can be empty.
4. **Type**: one of these words, or empty when none fits:
   - `word`: a word or an expression, with its meaning on the back.
   - `concept`: an idea, a term or a thing, explained on the back.
   - `quote`: a quote on the front, with who said it, and where, on the back.
   - `question`: a question on the front, with its answer on the back.
5. **Source**: where the card's content comes from, such as a book or a course. It can be empty.

Every line has all five columns: an empty column is nothing between two tabs, or after the last one. The front and the back always hold text.

A column that holds a line break or a double quote, or starts with `#`, goes in double quotes, with each double quote inside it written twice: `"He said ""yes""."`. Ficha skips a line that starts with `#` outside quotes, as a comment, and blank lines.

## An example

```text
#separator:tab
#html:false
#columns:Front	Back	Tags	Type	Source
#tags column:3
serendipity	Finding something good without looking for it.	vocabulary	word	
mitochondria	The part of a cell that turns food into the energy the cell uses.	biology cell_biology	concept	An introductory biology course
"""I think, therefore I am."""	René Descartes, in Discourse on the Method (1637).	philosophy	quote	
What is the capital of Mongolia?	Ulaanbaatar.	geography	question	
photosynthesis	"How plants make their food:
water + carbon dioxide + light → sugar + oxygen."	biology		
```

This file holds five cards:

- "serendipity", a word, with the tag "vocabulary".
- "mitochondria", a concept, with the tags "biology" and "cell biology", and its source.
- The quote "I think, therefore I am.", whose front is in quotes since it holds double quotes, each written twice, with the tag "philosophy".
- "What is the capital of Mongolia?", a question, with the tag "geography".
- "photosynthesis", with no type, whose back is in quotes since it takes two lines, with the tag "biology".
