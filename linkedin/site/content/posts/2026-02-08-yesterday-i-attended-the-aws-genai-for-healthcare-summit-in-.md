+++
title = "Yesterday, I attended the AWS GenAI for Healthcare Summit in Lisbon. "
date = "2025-06-19T10:13:00"
draft = false
[params]
  source = "linkedin"
  likes = 33
  views = 1118
  url = "https://www.linkedin.com/feed/update/urn:li:share:7341407690692116482"
  linkedin_analytics_url = "https://www.linkedin.com/analytics/post-summary/urn:li:activity:7341407692235689984/"
+++

Yesterday, I attended the AWS GenAI for Healthcare Summit in Lisbon. 

Here's my impressions for the day, and thanks Krishna Singh and Jens Dommel for inviting me!

# Where is the Medical Sector using (Gen)AI

A non-exhaustive list:

1. Clinical Decision Support
2. AI Buddy in Diagnostics
3. Enhancing Imaging
 For example, using AI to adjust X-ray imaging when there’s missing data, low resolution, cropping, or low contrast.
4. Data Storage Management
 Some institutions have kept all their digital X-ray images. Since storage is so costly they started leveraging AI to discard 70% of their data and reconstruct when needed from the remaining 30% without information loss.
5. Reducing Invasive Examinations
 Research suggests up to 5% of all cancers may be linked to exposure from CT scans. To avoid it, less precise scans can be used, making diagnosis harder. TheraPanacea trained a variational autoencoder on 250,000 CT scans to generate high-quality images from lower-quality scans. The demo results were impressive!

I found it fascinating that 3–5 are "human-out-of-the-loop" applications—offering scalable, software-like gains!

The most moving example, however, was a highly "human-in-the-loop," non-scalable solution. In Africa, there’s a shortage of radiologists and widespread tuberculosis. To help, a new portable X-ray box with built-in AI models is being used. It’s transported village-to-village by motorbike. Everyone in the village can be scanned, and if the AI flags someone’s scan, they’re referred to a hospital for specialized care. The motorcyclist doesn’t need medical training—the X-ray box and AI do the work!

hashtag#Challenges

Customized/fine-tuned foundational models for the medical **sub**domain is a must. That is, not only should models be specialized in health care: they should be specialized in the discipline within health care where they will be deployed. Why?

1. Medical accuracy (goes without saying
2. Clinical relevance
3. Direct access and quoting medical sources and evidence
4. Healthcare context understanding (steering the model towards prioritizing clinical info—which is something the models should be able to do already, but I suspect that there's a lot of improvised medical advice on the internet that a non-specialized model won't be steered enough by prompting alone)
5. A didactic approach in the replies geared towards what health professionals are used. I cannot validate this, but I've heard that general models tends to be terser in their replies by default. I don't know by which measure prompting can address it!

All these items contribute to *trust*, one of the big challenges in deploying AI in the medical sector. And with *trust*, *adoption* follows, and, from *adoption*, *impact*.

To close: everybody was screaming agents but there was no **agentic** demos

Maybe next year?





![Post image 2](/media/2026-02-08-yesterday-i-attended-the-aws-genai-for-healthcare-summit-in--image2.jpg)
