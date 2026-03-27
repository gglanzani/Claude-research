+++
title = "What's the impact of DeepSeek AI V3 and R1 on the hashtag#GenAI market and on coding in particular?"
date = "2025-02-13T13:01:00"
draft = false
[params]
  source = "linkedin"
  likes = 65
  views = 3438
  url = "https://www.linkedin.com/feed/update/urn:li:share:7295789109162246146"
  linkedin_analytics_url = "https://www.linkedin.com/analytics/post-summary/urn:li:activity:7295789112597368832/"
+++

What's the impact of DeepSeek AI V3 and R1 on the hashtag#GenAI market and on coding in particular?

Yesterday, our CEO Anand Sahay asked for my perspective, so I set aside two hours in my agenda to find out. Little did I know back then that writing this post would have taken longer than coding a whole web application leveraging DeepSeek.

To form a perspective, I didn't want to read what everyone was writing, but I set out to replicate with DeepSeek the application that I coded in ChatGPT in the summer of 2023 to send a reminder to our customers by SMS (see my blog post https://xebia.com/blog/how-i-learned-to-stop-worrying-and-love-llms/)

One of the application's goals back then was to be portable so that every colleague, even salespeople, could use it.

However, I didn't want Deepseek to rewrite it in Go: I wanted to learn something new, so I opted for an even easier app: a web page, all HTML and Javascript!

Lo and behold, after 15 minutes, I had a working web app (the only thing I had to update was the "Sender" field, as I didn't specify it in the prompt!), as you can see in the screenshot.

It works with your MessageBird API key, it asks who sends the message, and what text you want to send. 

Then, you need to upload a CVS file with names and phone numbers and it will send custom messages to your customers (in this case, the message was "Hi Giovanni, I'm testing deepseek-v3").

And the most amazing thing: thanks to DeepSeek's breakthrough technology, it was cheap, and you can run it on-premise or in the cloud (I opted for Fireworks.ai so that I could compare it with other models such as Mistral, Llama, and more).:

- I used 221 input tokens and 2834 output tokens
- Each million tokens costs 90 cents
- So, in total, coding this app cost me 0,27495 **cents**.

And, cherry on top, I could alternate using DeepSeek V3 and DeepSeek R1 (their reasoning model, which performs on par with the latest and greatest OpenAI model) to understand the reasons for certain choices so that I could correct it when necessary! Transparency is a big plus of DeepSeek when compared with the competition!

For the curious, here's the prompt I used for the initial coding exercise:
"Using the messagebird API, create an HTML page that allows me to input my messagebird API key, a CSV with names and phone numbers, and a text box in which I can enter the body of the SMS message that has to be sent via message bird to the phone numbers contained in the CSV file"





![Post image 2](/media/2026-02-08-what-s-the-impact-of-deepseek-ai-v3-and-r1-on-the-hashtag-ge-image2.jpg)
