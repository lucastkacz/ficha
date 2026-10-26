# Instructions for an AI: a file of cards for Ficha

Ficha is a flashcard app for the Mac: every so often it shows its user a small card, and it spaces each card by how well they know it. It imports cards from a text file, the same file it exports, or from a zip with that file and the cards' images and sounds, and these instructions say how to write one. In Ficha, "Copy Instructions for an AI" in the Cards window's Import sheet copies them, to paste into an AI chat along with what you want cards about. You can also follow them to write a file yourself.

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

Every line has all five columns: an empty column is nothing between two tabs, or after the last one. The front and the back always hold text, unless the card has an image or a sound, as the last sections say.

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

## Cards with images

A card's front or back can show an image too, such as a bird's photo on the front and its name on the back. Write cards with images only for images the user has, or will add, as files: you can't put an image in a text file.

- The header names two more columns after Source, `Front image` and `Back image`, with a tab between each name, and every line has all seven columns.
- Each of them holds the name of the image file for that side, such as `hornero.jpg`, or nothing when the side has no image. A side holds text, an image, or both: with an image, its text can be empty.
- The text file and the image files go in one zip, side by side: on a Mac, select them in Finder, choose Compress, and name the zip after the cards' subject, like `Birds.zip`. Ficha imports the zip, shrinks each image to about 1,600 pixels on its long side, and proposes the zip's name as a tag for every card. It reads the image formats a Mac opens, such as JPEG, PNG, HEIC and SVG.
- Answer with the text file as "What to do" says, and then one line telling the user to zip it with the images it names.

### An example with images

```text
#separator:tab
#html:false
#columns:Front	Back	Tags	Type	Source	Front image	Back image
#tags column:3
What bird is this?	The rufous hornero, which builds its nest of mud.	birds	question		hornero.jpg	
	The southern lapwing, which shouts when anyone nears its nest.	birds			lapwing.jpg	
```

This file holds two cards, each with the tag "birds", for a zip that also holds `hornero.jpg` and `lapwing.jpg`:

- "What bird is this?", a question, with the photo `hornero.jpg` on its front too.
- A card whose front is only the photo `lapwing.jpg`, with no text and no type.

## Cards with sounds

A card's front or back can play a sound too, such as a bird's song on the front and its name on the back. Ficha plays it only when the user asks. Write cards with sounds only for sounds the user has, or will add, as files: you can't put a sound in a text file.

- The header names two more columns after Source, `Front sound` and `Back sound`, with a tab between each name, and every line has all seven columns. When the cards have images too, the sound columns go after `Back image`, and every line has all nine columns.
- Each of them holds the name of the sound file for that side, such as `hornero.mp3`, or nothing when the side has no sound. A side holds text, an image, a sound, or any of them together: with an image or a sound, its text can be empty.
- The text file and the sound files go in one zip, side by side, with the images when there are any, as "Cards with images" says. Ficha converts each sound to a light format, about 1 MB a minute. It reads the sound formats a Mac plays, such as MP3, M4A, WAV and AIFF, and from a video it takes the sound.
- Answer with the text file as "What to do" says, and then one line telling the user to zip it with the sounds it names.

### An example with sounds

```text
#separator:tab
#html:false
#columns:Front	Back	Tags	Type	Source	Front sound	Back sound
#tags column:3
What bird sings like this?	The rufous hornero, which builds its nest of mud.	birds	question		hornero.m4a	
	The southern lapwing, which shouts when anyone nears its nest.	birds			lapwing.m4a	
```

This file holds two cards, each with the tag "birds", for a zip that also holds `hornero.m4a` and `lapwing.m4a`:

- "What bird sings like this?", a question, with the song `hornero.m4a` on its front too.
- A card whose front is only the call `lapwing.m4a`, with no text and no type.
