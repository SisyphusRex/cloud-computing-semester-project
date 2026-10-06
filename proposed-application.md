# Lecture Transcriber and Indexer
## The Problem
Recorded lectures are an integral teaching resource.  Without captions they are not accessible to many students, and without indexes, they are hard to search.

If a student can search for keywords in lecture videos, they can reduce the amount of time skipping through videos and focus on what they need to learn.

## The Goal
Our application should achieve two related purposes, uploading and searching.
Professors must be able to upload their lecture videos to our database and students must be able to search the videos's transcripts for keywords.
### First: Upload, Transcribe, and Index videos
#### Upload
Professors need to upload their video somewhere so that our application can access it and transcribe the audio.
We could store the videos ourselves, which may be expensive, or have the professor upload the video to their youtube channel separately and then provide the direct link to their video to our application. 
#### Transcribe
Our application must access and process the video somehow so that it can transcribe the audio into text.

#### Index
Store the transcriptions in an indexable or searchable database that allows searching of terms or keywords in the text.

### Second: Search
Students need to be able to search for important keywords and get a direct index into the video where that keyword appears in the transcript.  

For example, if the professor mentions "lambda calculus" in "Fall Lecture 4" at timestamp "03:22", if the student searches for "lambda calculus" then our app should return a link to the lecture video at that exact timestamp, or a list of links to all videos that mention "lambda calculus".

## Example Workflow
1. Professor records class video.
2. Professor uploads video to youtube.
3. Professor logs in to our app and provides link to his lecture video.
4. Our application accesses the video and begins transcribing it.
5. A student logs in to our app and searches for a keyword.
6. The app queries our database of transcripts and returns the video and timestamp.
7. The app forms a link to the video at that exact timestamp and returns it to the student.
8. Student clicks on the link and goes directly to the place in the video they need to learn.

## Cloud Native Justification
Students and professors are not giving lectures or studying all of the time.  The demand is variable and tends to be during the school year and during certain days and certain times of the day (during semester, weekdays, after class).  We do not need a large monolithic server running 24/7 to handle peak usage when the average use is low.  We want the application to be able to scale horizontally to meet demand.  It needs to scale to meet professor demand: uploading and transcribing, and it needs to scale to meet student demand: searching.
### Cost
Being able to scale and contract should reduce our costs versus running a large monolithic server application.



## Narrowing Scope
### Transcriptions
If we use youtube as our video host, we may be able to pull their captions if they have them as well.  That would mean we would not have to transcribe videos ourselves, merely put the captions into our database.

If we cannot get accurate captions from youtube, then we must transcribe them ourselves using a third party package like WhisperAI .

### Captions
Even though we are transcribing the videos so that we can search the transcriptions, we may not need to save the actual captions.  If we are hosting and serving the lecture videos ourselves, then we need to save the captions.  If we are relying on Youtube to host and serve the actual videos, then we need not caption the video, only save the transcripts to our database.

### Video Storage
Storing videos may be too expensive.  We should look into the cost of storing and serving videos and then see if we can just have youtube as the video host.  Youtube will add captions to their videos natively, but they do not allow searching and indexing into videos by the captions (thats where our server comes in)

