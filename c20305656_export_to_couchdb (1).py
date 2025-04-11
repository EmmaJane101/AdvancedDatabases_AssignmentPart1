import couchdb
import mariadb
import datetime
import json

# Setting up the connection to CouchDB
couch = couchdb.Server("http://admin:couchdb@127.0.0.1:5984")  
db_name = "music_comp"  

if db_name in couch:
    db = couch[db_name]
    couch.delete(db_name)
else:
    db = couch.create(db_name)

# Connect to the Mariadb relational database
db_config = {
    "host": "127.0.0.1",
    "user": "root",
    "password": "mariadb",
    "database": "MusicCompDB"
}

conn = mariadb.connect(**db_config)
cursor = conn.cursor()
cursor.execute("USE MusicCompDB") 


#Retrieve the data
fact_query = "SELECT viewerSK, participant_SK, TimeSK, vote, cost, voteMode FROM FactVote"
cursor.execute(fact_query)
fact_data = cursor.fetchall()


# Creating a single document for each fact merging dimension data into each fact document
for row in fact_data:
    vsk=int(row[0])
    psk=int(row[1])
    tsk=int(row[2])
    
    # Retrieve the viewer details
    cursor.execute("SELECT age_group_desc, v_countyName, voteCategory FROM DimViewer WHERE viewerSK = %s", (vsk,))
    viewer_details = cursor.fetchone()
    viewer_age_group = viewer_details[0] 
    viewer_countyName = viewer_details[1] 
    viewer_cat = viewer_details[2] 

    # Retreive the participant details
    cursor.execute("SELECT p_name, p_countyName FROM DimParticipant WHERE participant_SK = %s", (psk,))
    part_details = cursor.fetchone()
    part_name = part_details[0]
    part_countyName = part_details[1]
    
    # Retrieve the time details
    cursor.execute("SELECT Edition_Year, voteDate FROM DimTime WHERE TimeSK = %s", (tsk,))
    time_details = cursor.fetchone()
    edYear = time_details[0]
    vote_date = time_details[1]
    
    # converting the date object to a string as type date is not JSON serializable
    vote_date_str = vote_date.strftime("%Y-%m-%d")


    # Create a document for each fact 
    document = {
        "viewer_sk": row[0],
        "viewer_age_group": viewer_age_group,
        "viewer_county": viewer_countyName,
        "viewer_category": viewer_cat,
        "participant_sk": row[1],
        "participant_name": part_name,
        "participant_county": part_countyName,
        "timeSK": row[2],
        "edition_year": edYear,
        "vote_date": vote_date_str,
        "vote": row[3],
        "cost": row[4],
        "vote_mode": row[5],
    }

    # Insert the document into CouchDB
    db.save(document)

# Close the Mariadb database connection
conn.close()
