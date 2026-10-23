`Myway` is a minimalistic software for displaying results of photoshoots (or other organised collections of images) to a limited number of users.

# Key concepts

`Myway` displays images from a gallery that belongs to a collection:
 * **a collection** contains galleries; it is a top-level "namespace", separate from other collections
 * **a gallery** belongs to a single collection; it contains images that are displayed together
 * **an image** is a single image file that belongs to a single gallery
 
How does it look in practice:
 * a collection corresponds to a yaml file in `collections` directory; that yaml defines source directory for galleries, name and title, password and other things; when a collection is first accessed, a directory named after the collection will be created inside `collections` and will store all the relevant metadata 
 * a gallery is a directory within the source of the collection; its details can be specified in the gallery yaml file, which is located in the gallery's directory in `collections` 
 * images are, well, image files located directly in the gallery folder; a metadata file is created in the gallery's folder under `collections`

# User interaction

`Myway` supports limited user interaction based on user roles: 
 * **a visitor** browses a collection that may leave comments and react to images
 * **an owner** owns the collection and may modify its properties; has access to the admin page of the collection
 * **an admin** is responsible for the entire installation; has access to admin page of the entire installation and all the collections

# Requirements

`Myway` is written in Ruby and uses Sinatra as its web engine. Image Magick is required.

# Yaml files

`Myway` uses files to store most of its data.

## `collections/.config.yaml`

This file contains all the setup information.
```yaml
  title: "Display title for the site"
  theme: directory_name # located in themes, that directory contains various views; this is the default unless a collection overrides it
  admin:
      login: user_login # no other user can have that user login
      name: "Display name of the user"
      password: abc # required, will be created during setup
```

## `collections/{collection_name}/.collection.yaml`

This file defines the galleries, collection title, its allowed users, password, and so on. The name of the collection is already in the filename. It cannot start with a `.`.
```yaml
  title: "Display title for the collection"
  description: "long form description for the collection" # optional
  source: /directory/path # note that web server must have read access to this directory
  password: abc # optional, but if present, the collection cannot be accessed unless that password is entered
  owner: owner_login # corresponds to an entry in the users section; optional, when not present, the admin is the owner
  theme: directory_name # optional, defaults to whatever is the system-wide setting
  miniature: # when defined, allows overriding default miniature setting
    max_width: 320 # change either width or height to 0 to disable miniatures
    max_height: 320
  operations:
    allow_visitors: true # if false, no user interaction is allowed, and the option to create a user profile is not allowed
    allow_reactions: true # if false, no reaction buttons are shown
    allow_comments: true # if false, no comment form is shown
    reactions: [] # allowed reactions (shown in reaction buttons - ideally, these are unicode characters)
  visitors:
    - login: user_login
      name: "Display name of the user"
      password: abc # required, will be defined when the user sets up their profile
```

## `collections/{collection_name}/{gallery_name}/.gallery.yaml`

This file contains information related to the gallery. It is automatically created when enabling a gallery.
```yaml
  title: "Display title for the gallery" # optional, defaults to the file name
  description: "long form description for the gallery" # optional
  password: abc # optional, but if present, the gallery cannot be accessed unless that password is entered (this is in addition to the collection password)
```

## `collections/{collection_name}/{gallery_name}/{file_name}.yaml`

Every supported image file in the gallery directory has its own yaml with information about it.
```yaml
  title: "Display title of the image" # optional, defaults to file name
  reactions:
    - reaction: reaction_name
      visitors: [visitor_login_1, visitor_login_2...]
  comments:
    - author: visitor_login
      timestamp: timestamp_of_submission
      body: "comment body here; note that some sanity checks and filtering is done, this is expected to be plain text with minor markdown support"
```

# Miniatures

Miniatures of the original images are created using ImageMagick. The miniature is placed in `collections/{collection_name}/{gallery_name}/{file_name}.mini.jpg`.

# Templating


# Remarks

This software is free software, released under Apache license. See the `License` file for details.
This software is the result of human work.
