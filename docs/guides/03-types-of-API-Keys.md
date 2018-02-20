## Types of API Keys

In Carto, you can find 3 types of API Keys:


- Regular 
- Default public 
- Master 

#### Regular

Regular API Keys are, unsurprisingly, the most common type of API Keys. They provide access to APIs and Datasets in a granular and flexible manner.

  
For example one API key can provide access to 
  

- the SQL API 
- the World_Population dataset with read permission 
- the Liked_Cities dataset with read/insert permissions 
  

With this API Key you can, again unsurprisingly, access the SQL API but not the Maps API. You also can run a `SELECT SQL` query to the `World_Population` dataset, but not an `UPDATE`, `DELETE` or `INSERT`. Nevertheless, you can run an `INSERT` to the `Liked_Cities` dataset. Access to the dataset `National_Incomes` is denied.

  

It’s possible to create as many regular API Keys as you want. Moreover, to enforce security, we encourage you to create as many regular API Keys as apps/maps you produce. Since regular API Keys can be independently revoked, you have complete control of the lifecycle of your API credentials.

  

An important property to keep in mind about regular API Keys is that they are not editable. This means that once created the only way of modifying them is through this workaround:

  

1. Clone it 
2. Modify whatever you want 
3. Save the new API Key 
4. Deploy the new API Key to the appropriate maps/apps 
5. OPTIONAL: Delete the old API Key 
  

It’s designed this way on purpose for security reasons, sorry.

#### Default Public

Default public are a kind of regular API Keys. They too provide access to APIs and Datasets, but for the latter in a read-only way.

  

Every user has one and only one Default Public API Key. That means that on user creation a Default API Key is issued for that user, and that these type of keys are not revocable/deletable.

  

For example one Default Public API Key can provide access to 

  

- the SQL API 
- the Maps API 
- the World_Population dataset with read permission 
- the Liked_Cities dataset with read permission 
  

As you can see, API and read-only selected datasets access are possible.

  

At the beginning of this authentication section we stated that all API requests require an API Key. Well, we lied a little bit. If none is provided, the Default API Key is used as a fall back. This is done for backwards compatibility reasons. Don’t expect this behaviour to be maintained in the long term, it can be deprecated. Get used to always send an API Key, even if it’s the Default Public.

  

A cosmetic difference compared to the other API Key types is the code/token that identifies these API Keys, it’s just: _default_public_. It’s a simple human-readable constant string, no randoms involved.

#### Master

Master keys are a very special kind of API Keys. As it happens with the Default Public type, every user has one and only one Master non revocable API Key.

  

The special thing about Master API Keys is that they grant access to EVERYTHING: APIs and Datasets (read/insert/create/delete). Additionally, a Master API Key is required to access Auth API.

  

Your Master API key carries many privileges, so be sure to keep it secret! Do not share it in publicly accessible areas such as GitHub or client-side code. If you think is has been compromised, regenerate it immediately.

  

Actually, you should use Master API Keys sparingly. Try to limit its direct use only to interact programmatically with the [Auth API]({{site.authapi_docs}}/reference/). Issue and use regular API Keys for the rest of use cases.