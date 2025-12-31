//Primeiro criar as constraint 

CREATE CONSTRAINT music_id IF NOT EXISTS
FOR (m:Music)
REQUIRE m.track_id IS UNIQUE;

CREATE CONSTRAINT artist_name IF NOT EXISTS
FOR (a:Artist)
REQUIRE a.nome_artista IS UNIQUE;

CREATE CONSTRAINT genre_name IF NOT EXISTS
FOR (g:Genre)
REQUIRE g.nome_genero IS UNIQUE;

CREATE CONSTRAINT user_id IF NOT EXISTS
FOR (u:User)
REQUIRE u.id IS UNIQUE;


//Carregando dataset de spotify, criando os nos de Genero,Artista, Musica e ralacionamento de artista com musica,musica com genero.
//dados são carregado em forma de batch

LOAD CSV WITH HEADERS FROM 'https://drive.google.com/u/0/uc?id=1h-fMxYg956xfkws2yIeYeflmrCbgYV2Q&export=download' AS row

CALL {
  WITH row

  MERGE (a:Artist {nome_artista: row.artist_name})

  MERGE (g:Genre {nome_genero: row.genre})

  MERGE (m:Music {track_id: row.track_id})
  SET
    m.name = row.track_name,
    m.album = row.album_name,
    m.release_date = row.release_date,
    m.duration_ms = toInteger(row.duration_ms),
    m.popularity = toInteger(row.popularity),
    m.danceability = toFloat(row.danceability),
    m.energy = toFloat(row.energy),
    m.key = toInteger(row.key),
    m.loudness = toFloat(row.loudness),
    m.mode = toInteger(row.mode),
    m.instrumentalness = toFloat(row.instrumentalness),
    m.tempo = toFloat(row.tempo)

  MERGE (a)-[:CREATED]->(m)
  MERGE (m)-[:BELONGS_TO]->(g)

} IN TRANSACTIONS OF 1000 ROWS;

//Criando grafo temporario na memoria banco Neo4j de musica para ser usada no ML de KNN
CALL gds.graph.project(
  'musicGraph',
  'Music',
  '*',
  {
    nodeProperties: ['danceability', 'energy','tempo']
  }
);


//Calcular as similaridade entre músicas usando KNN e grava no banco relações SIMILAR_TO entre músicas parecidas, 
//com um score de similaridade. No topK estou colocando algoritmo procurar 5 musicas mais parecidas 
//e criar 5 relações similares for maior e igual 0.85. O comando writeRelationshipType vai gravar no banco o resultado ele
//cria (:Music)-[:SIMILAR_TO]->(:Music)


CALL gds.knn.write(
  'musicGraph',
  {
    nodeProperties: ['danceability', 'energy', 'tempo'],
    topK: 5,
    similarityCutoff: 0.85,
    writeRelationshipType: 'SIMILAR_TO',
    writeProperty: 'score'
  }
);


// Fazendo teste de uma música "Last free" qual é similariedade dela com outras musicas e score

MATCH (m:Music {name: "Last free"})-[r:SIMILAR_TO]->(s:Music)
RETURN m, r, s
ORDER BY r.score DESC
LIMIT 10;


//Lista as músicas que têm mais conexões de similaridade, 
//ou seja, as músicas que o KNN considera “parecidas com muitas outras”.

MATCH (m:Music)-[:SIMILAR_TO]-()
RETURN m.name, count(*) AS conexoes
ORDER BY conexoes DESC
LIMIT 10;

//Mostra pares de músicas extremamente parecidas, com similaridade maior que 0.85, segundo o KNN.
//Aqui ele vai responder “as músicas que o modelo considera muito parecidas realmente fazem sentido?”

MATCH (m1:Music)-[r:SIMILAR_TO]->(m2:Music)
WHERE r.score > 0.85
RETURN m1, r, m2
LIMIT 50;


//Validação o KNN 
MATCH ()-[r:SIMILAR_TO]->()
RETURN
  count(r) AS total_relacoes,
  avg(r.score) AS score_medio,
  max(r.score) AS score_max;


/// Realizando um carregando aletorio de base usuarios que ouviu musicas e curtir e criando os relacionamentos

LOAD CSV WITH HEADERS FROM 'https://drive.google.com/u/0/uc?id=1ePLuAwbwwwTR0nQHYLweU_HvaanUODyd&export=download' AS row
MERGE  (u:User {id: row.user_id})
MATCH (m:Music {track_id: row.track_id})


WITH u, m, row
WHERE row.interaction = 'LISTENED'
MERGE (u)-[:LISTENED {count: toInteger(row.listen_count)}]->(m);


WITH u, m, row
WHERE row.interaction = 'LIKED'
MERGE (u)-[:LIKED]->(m);


//Recomenda músicas para o usuário user_0001, 
//com base nas músicas que ele ouviu e na similaridade entre músicas calculada pelo KNN.

MATCH (u:User {id:'user_0001'})-[:LISTENED]->(m1)-[s:SIMILAR_TO]->(m2)
RETURN m2.name, s.score
ORDER BY s.score DESC
LIMIT 10;
