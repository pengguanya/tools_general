#!/usr/bin/env python3
import secrets
import string

def generate_password(min_length=15, max_length=25):
    # Define character sets
    uppercase = string.ascii_uppercase
    lowercase = string.ascii_lowercase
    digits = string.digits
    allowed_symbols = "\"%&'()*+,-./:;<=>?!"
    # ? and ! cannot be the first character
    first_char_symbols = "\"%&'()*+,-./:;<=>".replace(" ", "")

    # For the first character: letters, digits, and symbols except ? and !
    first_allowed = uppercase + lowercase + digits + first_char_symbols
    # For the rest, combine all allowed characters.
    all_chars = uppercase + lowercase + digits + allowed_symbols

    # Determine a random length within the allowed range.
    length = secrets.choice(range(min_length, max_length + 1))
    
    # Select the first character from letters only.
    password = [secrets.choice(first_allowed)]
    
    # Fill the rest of the password randomly.
    for _ in range(1, length):
        password.append(secrets.choice(all_chars))
    
    password = ''.join(password)
    
    # Validate the password meets required conditions:
    # Must contain at least one digit, one uppercase, and one lowercase letter.
    if (any(c.isdigit() for c in password) and
        any(c.islower() for c in password) and
        any(c.isupper() for c in password)):
        return password
    else:
        # If the password doesn't satisfy the conditions, generate a new one.
        return generate_password(min_length, max_length)

# Example usage:
print("Generated password:", generate_password())
