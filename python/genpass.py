import secrets
import string

def generate_password(min_length=15, max_length=25):
    # Define character sets
    uppercase = string.ascii_uppercase
    lowercase = string.ascii_lowercase
    digits = string.digits
    allowed_symbols = "%&#-=+"
    
    # For the first character, only letters are allowed.
    first_allowed = uppercase + lowercase
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
