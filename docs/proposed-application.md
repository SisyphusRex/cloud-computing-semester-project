# Lecture Transcriber and Indexer
## The Problem
Recorded lectures are an integral teaching resource.  Searching for topics mentioned in videos is difficult.

If a student can search for keywords in lecture videos, they can reduce the amount of time skipping through videos and focus on what they need to learn.

# Workflow
1. Professors upload their lecture video to youtube
2. The professor logs into our app and provides a link to their video and authorizes our app to get the captions
3. Our app calls the youtube api and gets the transcript
4. We put the transcript in a database that is searchable by keyword and has timestamps
5. Students log into our app
6. They enter a keyword they want to know more about
7. The app returns the video at the exact timestamp the keyword was mentioned


## Cloud Native Justification
Students and professors are not giving lectures or studying all of the time.  The demand is variable and tends to be during the school year and during certain days and certain times of the day (during semester, weekdays, after class).  We do not need a large monolithic server running 24/7 to handle peak usage when the average use is low.  We want the application to be able to scale horizontally to meet demand.  It needs to scale to meet professor demand: uploading and transcribing, and it needs to scale to meet student demand: searching.
### Cost
Being able to scale and contract should reduce our costs versus running a large monolithic server application.





# Our main Goal
Make lecture videos uploaded to youtube and provided to our application by the professors searchable by keyword through their transcriptions, and return a timestamp of exactly where the keyword was mentioned and in which video.  A professor provides a youtube link and authorizes our application to call the api and get the transcript.  We store the transcript in a database that is searchable.  We then let the students search for a keyword.  We then provide the video at the exact timestamp if it is found using embedded youtube videos so we don't have to host.

# Use Google Identity Platform
To be able to get transcripts from an instructor's videos via Youtubes API, they have to use google's OAUTH .  We should make our login use google instead of Entra.
https://developers.google.com/youtube/v3/guides/authentication

# Remove the active transcription functionality
We will rely on youtube's transcription retrieved through the api.
In scope: Youtube videos with transcripts
Out of scope: generating captions
Adding transcription services could be a future goal.

# Search Type
We are not testing semantic, hybrid, or keyword search versus one another.  The purpose of this application is to just search the captions of lecture videos and be cloud native.  Adding other search methods could be a future goal.

# Simplify the Evaluation
We will evaluate the project success by demonstrating:
1. That we can deploy the application to the respective cloud services.
2. That the application functions as intended:
    a. allows users to sign in with google id
    b. gets transcripts of videos professors want to add
    c. allows students to search by keyword the transcripts of videos
    d. displays the video at the correct timestamp using embedded youtube
3. That the application scales under load
4. That we can monitor the application and resources
5. That we implement security
6. The cost effectiveness of our scaling approach to a large vm


